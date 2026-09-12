import Foundation

// fine — Fine CLI. 앱의 제어 소켓(~/.fine/control.sock)에 JSON 한 줄을 보내고
// 응답을 사람이 읽기 좋게, 또는 --json으로 그대로 출력한다. 앱이 안 떠 있으면 띄우고 기다린다.

let socketPath = (NSHomeDirectory() as NSString).appendingPathComponent(".fine/control.sock")
let bundleID = "com.seol.fine"

let usage = """
fine — Fine을 터미널에서 조작한다

  fine windows                              창 목록
  fine window new                           새 창
  fine window focus|close <win>             창 앞으로/닫기

  fine list [--harness H] [-n N]            최근 대화 (claude|codex|opencode)
  fine new [--harness H] [--model M] [--effort E] [--proxy] [prompt…]
                                            새 대화 (지정 안 한 값은 컴포저의 현재 기본값)
  fine resume <session-id> [--harness H]    대화 이어서 열기
  fine restart <tab> [--model M] [--effort E]
                                            같은 대화를 다른 모델로 재시작

  fine tabs                                 탭 목록 (모든 창)
  fine tab select|close <tab>               탭 선택/닫기
  fine tab next|prev                        다음/이전 탭
  fine tab move <tab> <index|+1|-1>         탭 순서 이동
  fine home                                 홈(새 대화 화면)으로

  fine models [--harness H]                 하네스가 아는 모델·effort
  fine state                                window-states.json 덤프
  fine ping

옵션: --json (원본 JSON), -w/--window <index|id 접두사|front>, --no-focus
<win>은 index / id 접두사 / front, <tab>은 index / 이름 / session-id / id 접두사
--model default 는 "기본 (터미널과 동일)"
"""

struct CLIError: Error { let message: String }

func send(_ command: String, _ args: [String: Any]) throws -> [String: Any] {
    if !FileManager.default.fileExists(atPath: socketPath) {
        FileHandle.standardError.write("fine: Fine not running — launching…\n".data(using: .utf8)!)
        let open = Process(); open.executableURL = URL(fileURLWithPath: "/usr/bin/open"); open.arguments = ["-g", "-b", bundleID]
        try open.run(); open.waitUntilExit()
        let deadline = Date().addingTimeInterval(15)
        while !FileManager.default.fileExists(atPath: socketPath) && Date() < deadline { usleep(200_000) }
        usleep(300_000)   // 첫 창의 ContentView가 WindowOpener를 등록할 시간
    }
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw CLIError(message: "socket: \(String(cString: strerror(errno)))") }
    defer { close(fd) }
    var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(socketPath.utf8CString)
    withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes.map { UInt8(bitPattern: $0) }) }
    let rc = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
    guard rc == 0 else { throw CLIError(message: "cannot connect to \(socketPath): \(String(cString: strerror(errno))) — is Fine (with control server) running?") }
    var payload = try JSONSerialization.data(withJSONObject: ["command": command, "args": args])
    payload.append(UInt8(ascii: "\n"))
    payload.withUnsafeBytes { raw in _ = write(fd, raw.baseAddress!, raw.count) }
    var data = Data(); var buf = [UInt8](repeating: 0, count: 65536)
    while true { let n = read(fd, &buf, buf.count); if n <= 0 { break }; data.append(buf, count: n); if data.last == UInt8(ascii: "\n") { break } }
    guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CLIError(message: "bad response") }
    if obj["ok"] as? Bool != true { throw CLIError(message: obj["error"] as? String ?? "unknown error") }
    return obj
}

// MARK: - 인자 파싱

var argv = Array(CommandLine.arguments.dropFirst())
var wantJSON = false
var windowArg: String?
var noFocus = false
var positional: [String] = []
var flags: [String: String] = [:]
var i = 0
while i < argv.count {
    let a = argv[i]
    switch a {
    case "--json": wantJSON = true
    case "--no-focus": noFocus = true
    case "-w", "--window": i += 1; windowArg = i < argv.count ? argv[i] : nil
    case "--proxy": flags["proxy"] = "true"
    case "--harness", "--model", "--effort", "-n", "--limit":
        i += 1; flags[a.hasPrefix("--") ? String(a.dropFirst(2)) : "limit"] = i < argv.count ? argv[i] : ""
    case "-h", "--help", "help": print(usage); exit(0)
    default: positional.append(a)
    }
    i += 1
}
guard let group = positional.first else { print(usage); exit(1) }
let sub = positional.count > 1 ? positional[1] : nil
let rest = Array(positional.dropFirst(2))
var args: [String: Any] = [:]
if let windowArg { args["window"] = windowArg }
if noFocus { args["focus"] = false }
if let h = flags["harness"] { args["harness"] = h }

func need(_ n: Int, _ what: String) throws -> [String] {
    guard rest.count >= n else { throw CLIError(message: "usage: \(what)") }
    return rest
}

func modelFlags() {
    if let m = flags["model"] { args["model"] = m }
    if let e = flags["effort"] { args["effort"] = e }
}

let command: String
do {
    switch (group, sub) {
    case ("ping", _): command = "ping"
    case ("windows", _): command = "windows.list"
    case ("window", "new"): command = "window.new"
    case ("window", "focus"), ("window", "close"):
        command = "window.\(sub!)"; args["window"] = try need(1, "fine window \(sub!) <win>")[0]
    case ("list", _), ("conversations", _):
        command = "conversations.list"; args["limit"] = Int(flags["limit"] ?? "30") ?? 30
    case ("new", _):
        command = "session.new"
        let prompt = Array(positional.dropFirst()).joined(separator: " ")
        if !prompt.isEmpty { args["prompt"] = prompt }
        modelFlags(); if flags["proxy"] != nil { args["proxy"] = true }
    case ("resume", _):
        guard let id = sub else { throw CLIError(message: "usage: fine resume <session-id>") }
        command = "session.resume"; args["id"] = id
    case ("restart", _):
        guard let tab = sub else { throw CLIError(message: "usage: fine restart <tab> [--model M] [--effort E]") }
        command = "tab.restart"; args["tab"] = tab; modelFlags()
    case ("tabs", _), ("tab", nil), ("tab", "list"): command = "tab.list"
    case ("tab", "select"), ("tab", "close"): command = "tab.\(sub!)"; args["tab"] = try need(1, "fine tab \(sub!) <tab>")[0]
    case ("tab", "next"), ("tab", "prev"): command = "tab.\(sub!)"
    case ("tab", "move"):
        let a = try need(2, "fine tab move <tab> <index|+1|-1>"); command = "tab.move"; args["tab"] = a[0]; args["to"] = a[1]
    case ("home", _): command = "home"
    case ("models", _): command = "models.list"
    case ("state", _): command = "state.dump"
    default: throw CLIError(message: "unknown command: \(positional.joined(separator: " "))\n\n\(usage)")
    }
    let response = try send(command, args)
    let result = response["result"] ?? NSNull()
    if wantJSON {
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    } else {
        print(render(command: command, result: result))
    }
} catch let error as CLIError {
    FileHandle.standardError.write("fine: \(error.message)\n".data(using: .utf8)!)
    exit(1)
} catch {
    FileHandle.standardError.write("fine: \(error)\n".data(using: .utf8)!)
    exit(1)
}

// MARK: - 사람이 읽는 출력

func render(command: String, result: Any) -> String {
    func table(_ rows: [[String]]) -> String {
        guard let first = rows.first else { return "(none)" }
        var widths = Array(repeating: 0, count: first.count)
        for row in rows { for (i, c) in row.enumerated() where i < widths.count { widths[i] = max(widths[i], c.count) } }
        return rows.map { row in row.enumerated().map { i, c in i == row.count - 1 ? c : c.padding(toLength: widths[i], withPad: " ", startingAt: 0) }.joined(separator: "  ") }.joined(separator: "\n")
    }
    func short(_ id: Any?) -> String { String((id as? String ?? "").prefix(8)).lowercased() }
    // JSON의 true/false와 0/1은 둘 다 NSNumber로 들어오므로 CFBoolean인지로 구분한다.
    func str(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "yes" : "" }
            return n.stringValue
        }
        return ""
    }
    func model(_ t: [String: Any]) -> String {
        let m = str(t["model"]); if m.isEmpty { return "default" }
        return (t["efforts"] == nil && !str(t["effort"]).isEmpty) ? "\(m) / \(str(t["effort"]))" : m
    }
    func tabRow(_ i: Int, _ t: [String: Any]) -> [String] {
        [String(i), str(t["selected"]) == "yes" ? "*" : "", str(t["harness"]), str(t["name"]), model(t),
         str(t["running"]) == "yes" ? "running" : "idle", short(t["id"]), String(str(t["sessionId"]).prefix(12))]
    }
    let header = ["#", "", "harness", "name", "model", "state", "id", "session"]
    switch command {
    case "windows.list":
        let rows = (result as? [[String: Any]] ?? []).map { w in
            [str(w["index"]), short(w["id"]), str(w["isKey"]) == "yes" ? "*" : "", str(w["title"]), "\(str(w["tabCount"])) tabs"]
        }
        return table([["#", "id", "key", "title", ""]] + rows)
    case "tab.list", "tab.move":
        let rows = (result as? [[String: Any]] ?? []).map { t in ["w\(str(t["windowIndex"]))"] + tabRow(Int(str(t["index"])) ?? 0, t) }
        return table([["win"] + header] + rows)
    case "tab.select", "tab.next", "tab.prev", "tab.restart", "session.new", "session.resume":
        guard let t = result as? [String: Any] else { return "\(result)" }
        return table([header, tabRow(Int(str(t["index"])) ?? 0, t)])
    case "conversations.list":
        let rows = (result as? [[String: Any]] ?? []).map { c in [str(c["harness"]), str(c["id"]), String(str(c["modifiedAt"]).prefix(16)), str(c["title"])] }
        return table([["harness", "session-id", "modified", "title"]] + rows)
    case "models.list":
        guard let dict = result as? [String: Any] else { return "\(result)" }
        let rows = (dict["models"] as? [[String: Any]] ?? []).map { m in
            [str(m["id"]).isEmpty ? "default" : str(m["id"]), str(m["displayName"]), (m["efforts"] as? [String] ?? []).joined(separator: ",")]
        }
        let note = "harness: \(str(dict["harness"]))" + (str(dict["routerAvailable"]) == "yes" ? "  (router 127.0.0.1:4141)" : "")
        return note + "\n" + table([["id", "name", "efforts"]] + rows)
    default:
        if let dict = result as? [String: Any] {
            return dict.keys.sorted().map { k in "\(k): \(str(dict[k]).isEmpty ? "\(dict[k] ?? "")" : str(dict[k]))" }.joined(separator: "\n")
        }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) { return String(decoding: data, as: UTF8.self) }
        return "\(result)"
    }
}
