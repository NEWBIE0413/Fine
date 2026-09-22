import Foundation

// fine — Fine CLI. 앱의 제어 소켓(~/.fine/control.sock)에 JSON 한 줄을 보내고
// 응답을 사람이 읽기 좋게, 또는 --json으로 그대로 출력한다. 앱이 안 떠 있으면 띄우고 기다린다.

let dataHome = ProcessInfo.processInfo.environment["FINE_HOME"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? NSHomeDirectory()
let socketPath = (dataHome as NSString).appendingPathComponent(".fine/control.sock")
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

  fine read <tab> [lines]                   탭 화면 읽기 (tmux capture-pane)
  fine send <tab> <text>                    탭에 글자 입력 (헤더·Enter 없음)
  fine keys <tab> <key…>                    특수키 (Enter, Escape, C-c, Up …)
  fine msg <tab|%pane> <text>               smux 헤더를 붙여 메시지 (읽기 → msg → keys Enter)
  fine transcript <tab> [-n N]              대화 본문 (하네스 transcript에서 구조화)
  fine id                                   이 탭의 fine:<UUID> 주소 (FINE_TAB_ID)
  fine resolve <target>                    고정 주소로 해석
  fine trust|untrust <target>               승인된 대화 범위 등록/해제

  fine models [--harness H]                 하네스가 아는 모델·effort
  fine state                                window-states.json 덤프
  fine appearance [system|light|dark]       외형 조회/변경 (즉시 적용)
  fine doctor                               준비 상태와 빠진 것을 채우는 명령
  fine theme <tab>                          그 탭의 터미널이 실제로 쓰는 색
  fine ping

옵션: --json (원본 JSON), -w/--window <index|id 접두사|front>, --no-focus
<win>은 index / id 접두사 / front, <tab>은 index / 이름 / session-id / id 접두사
--model default 는 "기본 (터미널과 동일)"

메시징은 smux 프로토콜과 같다: read로 상대를 먼저 보고, msg로 보내고, read로 확인한 뒤 keys Enter.
대상: Fine 탭 이름/ID, %pane, tmux:라벨, arch:라벨, mac:fine:<UUID>.
읽기 가드·trust·첫 연락·답장 주소는 tmux-bridge가 공통으로 처리한다.
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
    guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { throw CLIError(message: "socket path is too long") }
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

// MARK: - 공통 smux 프로토콜

/// Fine 이름은 Fine 탭, %pane은 tmux, host:target은 원격. tmux 라벨은
/// tmux:label로 명시해 같은 이름의 Fine 탭과 혼동하지 않는다.
func bridgeTarget(_ target: String) -> String {
    if target.hasPrefix("tmux:") { return String(target.dropFirst(5)) }
    if target.hasPrefix("%") || target.contains(":") { return target }
    return "fine:" + target
}

func bridge(_ command: String, _ target: String, _ arguments: [String]) throws -> Never {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["tmux-bridge", command, bridgeTarget(target)] + arguments
    process.standardInput = FileHandle.standardInput
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    try process.run()
    process.waitUntilExit()
    exit(process.terminationStatus)
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
    // Once a messaging target is parsed, remaining argv is literal payload.
    if ["send", "msg", "message", "keys"].contains(positional.first ?? ""), positional.count >= 2 {
        positional.append(a); i += 1; continue
    }
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
    case ("id", _):
        guard let raw = ProcessInfo.processInfo.environment["FINE_TAB_ID"], let tab = UUID(uuidString: raw) else {
            throw CLIError(message: "not running inside a Fine tab (FINE_TAB_ID is unset)")
        }
        print("fine:" + tab.uuidString.lowercased()); exit(0)
    case ("read", _), ("resolve", _), ("trust", _), ("untrust", _):
        guard let target = sub else { throw CLIError(message: "usage: fine \(group) <target>") }
        try bridge(group, target, rest)
    case ("send", _), ("keys", _), ("msg", _), ("message", _):
        guard let target = sub, !rest.isEmpty else { throw CLIError(message: "usage: fine \(group) <target> <text/key…>") }
        try bridge(group == "send" ? "type" : group, target,
                   group == "keys" ? rest : [rest.joined(separator: " ")])
    default: break
    }
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
    case ("transcript", _):
        guard let tab = sub else { throw CLIError(message: "usage: fine transcript <tab> [-n N]") }
        command = "tab.transcript"; args["tab"] = tab; args["limit"] = Int(flags["limit"] ?? "20") ?? 20
    case ("appearance", _):
        command = "appearance"
        // 값을 안 주면 현재 상태만 묻는다.
        if let mode = sub { args["mode"] = mode }
    case ("home", _): command = "home"
    case ("models", _): command = "models.list"
    case ("theme", _):
        guard let tab = sub else { throw CLIError(message: "usage: fine theme <tab>") }
        command = "tab.theme"; args["tab"] = tab
    case ("doctor", _): command = "doctor"
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
    case "tab.transcript":
        guard let dict = result as? [String: Any] else { return "\(result)" }
        return (dict["messages"] as? [[String: Any]] ?? []).map { m in
            "[\(String(str(m["timestamp"]).prefix(16))) \(str(m["role"]))] \(str(m["text"]))"
        }.joined(separator: "\n\n")
    case "doctor":
        guard let dict = result as? [String: Any] else { return "\(result)" }
        // 표가 아니라 목록으로 낸다 — 고칠 명령이 항목에 딸려 나와야 그대로 실행할 수 있다.
        var lines: [String] = []
        for check in dict["checks"] as? [[String: Any]] ?? [] {
            let ok = str(check["ok"]) == "yes"
            let optional = str(check["optional"]) == "yes"
            let mark = ok ? "✓" : (optional ? "·" : "✗")
            lines.append("\(mark) \(str(check["name"]))  \(str(check["detail"]))")
            if !ok, let fix = check["fix"] as? String, !fix.isEmpty {
                lines.append("    → \(fix)")
            }
        }
        lines.append("")
        lines.append(str(dict["summary"]))
        return lines.joined(separator: "\n")

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
