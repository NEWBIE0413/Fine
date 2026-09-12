import Foundation

/// CLI가 보내는 한 요청. 한 연결에 JSON 한 줄, 응답 한 줄.
struct ControlRequest {
    let command: String
    let args: [String: Any]

    func string(_ key: String) -> String? {
        if let s = args[key] as? String { return s }
        if let n = args[key] as? NSNumber { return n.stringValue }
        return nil
    }
    func bool(_ key: String) -> Bool? { args[key] as? Bool }
    func int(_ key: String) -> Int? {
        if let n = args[key] as? Int { return n }
        if let s = args[key] as? String { return Int(s) }
        return nil
    }
}

enum ControlResponse {
    case ok(Any)
    case error(String)

    var json: [String: Any] {
        switch self {
        case .ok(let result): return ["ok": true, "result": result]
        case .error(let message): return ["ok": false, "error": message]
        }
    }
}

/// UNIX 도메인 소켓 제어 서버. 앱 안에서 돌며 `fine` CLI의 요청을 메인 스레드로 넘긴다.
///
/// 왜 소켓인가: 창별 AppState는 프로세스 안에만 있고, 상태 파일(window-states.json)을
/// 밖에서 고치면 실행 중인 앱과 어긋난다. CLI가 "앱 내 기능 전부"를 쓰려면 앱 자신이
/// 명령을 받아야 한다. 프로토콜은 줄 단위 JSON — 어떤 언어의 스크립트도 붙을 수 있다.
final class ControlServer {
    typealias Handler = (ControlRequest, @escaping (ControlResponse) -> Void) -> Void

    static let maxRequestBytes = 1 << 20

    private let path: String
    private let handler: Handler
    private var listenFD: Int32 = -1
    private var lockFD: Int32 = -1
    private var ownsSocket = false
    private let acceptQueue = DispatchQueue(label: "Fine.control.accept", qos: .utility)

    init(path: String, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
    }

    func start() throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        // A second instance must not unlink the running app's socket. HOME alone
        // does not isolate Foundation paths on macOS (Fine bridge E2E incident).
        let lock = open(path + ".lock", O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw ControlError.system("socket lock", errno) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            close(lock); throw ControlError.system("another Fine owns this socket", EADDRINUSE)
        }
        lockFD = lock
        var started = false
        defer { if !started { stop() } }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ControlError.system("socket", errno) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8CString)
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd); throw ControlError.system("path too long", ENAMETOOLONG)
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: pathBytes.map { UInt8(bitPattern: $0) })
        }
        let active = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        guard !active else {
            close(fd); throw ControlError.system("another Fine is listening", EADDRINUSE)
        }
        var existing = stat()
        if lstat(path, &existing) == 0 {
            guard existing.st_mode & mode_t(S_IFMT) == mode_t(S_IFSOCK) else {
                close(fd); throw ControlError.system("socket path is not a socket", EEXIST)
            }
            unlink(path)
        }
        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else { let e = errno; close(fd); throw ControlError.system("bind", e) }
        ownsSocket = true
        chmod(path, 0o600)   // 같은 사용자만
        guard listen(fd, 16) == 0 else { let e = errno; close(fd); throw ControlError.system("listen", e) }
        listenFD = fd
        acceptQueue.async { [weak self] in self?.acceptLoop(fd) }
        started = true
    }

    func stop() {
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        if ownsSocket { unlink(path); ownsSocket = false }
        if lockFD >= 0 { close(lockFD); lockFD = -1 }
    }

    private func acceptLoop(_ fd: Int32) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            var enabled: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
            DispatchQueue.global(qos: .utility).async { [weak self] in self?.serve(client) }
        }
    }

    private func serve(_ client: Int32) {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)
        readLoop: while data.count < Self.maxRequestBytes {
            let n = read(client, &buffer, buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
            if data.last == UInt8(ascii: "\n") { break readLoop }
        }
        let finish: (ControlResponse) -> Void = { response in
            var out = (try? JSONSerialization.data(withJSONObject: response.json)) ?? Data()
            out.append(UInt8(ascii: "\n"))
            out.withUnsafeBytes { raw in
                var offset = 0
                while offset < raw.count {
                    let n = write(client, raw.baseAddress! + offset, raw.count - offset)
                    if n <= 0 { break }
                    offset += n
                }
            }
            close(client)
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let command = obj["command"] as? String else {
            finish(.error("invalid request: expected {\"command\": ..., \"args\": {...}}"))
            return
        }
        let request = ControlRequest(command: command, args: obj["args"] as? [String: Any] ?? [:])
        DispatchQueue.main.async { [handler] in handler(request, finish) }
    }

    enum ControlError: Error, CustomStringConvertible {
        case system(String, Int32)
        var description: String {
            switch self { case .system(let what, let code): return "\(what): \(String(cString: strerror(code)))" }
        }
    }
}
