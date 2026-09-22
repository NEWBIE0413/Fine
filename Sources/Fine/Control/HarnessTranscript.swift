import Foundation

/// `fine transcript`: 탭이 붙어 있는 대화의 본문을 하네스별 저장소에서 구조화해 읽는다.
/// 화면 캡처(`fine read`)와 달리 잘리거나 겹쳐 그려진 TUI가 아니라 실제 메시지를 돌려준다 —
/// Fine이 탭의 session id를 알기 때문에 가능한, tmux에는 없는 경로다.
enum HarnessTranscript {
    struct Message: Equatable {
        let role: String        // user | assistant
        let text: String
        let timestamp: Date?

        var json: [String: Any] {
            ["role": role, "text": text, "timestamp": timestamp.map { ISO8601DateFormatter().string(from: $0) } ?? ""]
        }
    }

    static func messages(harness: QuickHarness, sessionID: String, limit: Int,
                         claudeDirectory: URL = QuickConversationScanner.defaultTranscriptsDirectory(),
                         codexSessionsDirectory: URL = FinePaths.codexHome().appendingPathComponent("sessions"),
                         store: HarnessSessionStore = .local) -> [Message]? {
        let limit = min(500, max(0, limit))
        guard limit > 0 else { return [] }
        switch harness {
        case .claude:
            let file = claudeDirectory.appendingPathComponent("\(sessionID).jsonl")
            guard let data = try? Data(contentsOf: file) else { return nil }
            return Array(parseClaude(data).suffix(limit))
        case .codex:
            guard let file = codexRollout(sessionID: sessionID, in: codexSessionsDirectory),
                  let data = try? Data(contentsOf: file) else { return nil }
            return Array(parseCodex(data).suffix(limit))
        case .opencode:
            return store.openCodeMessages(sessionID: sessionID, limit: limit)
        case .omp:
            guard let session = OmpSessionResolver.session(id: sessionID),
                  let data = try? Data(contentsOf: session.url) else { return nil }
            return Array(parseOmp(data).suffix(limit))
        }
    }

    /// Claude transcript: type user/assistant, message.content는 문자열 또는 블록 배열.
    /// 도구 결과·명령 메타(<command-…>)·인터럽트 마커는 대화가 아니므로 뺀다.
    /// omp의 한 줄은 `{type, message: {role, content: [...]}}`이다.
    /// `thinking` 블록은 화면에 내보내지 않는다 — 대화가 아니라 과정이다.
    static func parseOmp(_ data: Data) -> [Message] {
        lines(data).compactMap { obj in
            guard obj["type"] as? String == "message",
                  let message = obj["message"] as? [String: Any],
                  let role = message["role"] as? String,
                  role == "user" || role == "assistant",
                  let blocks = message["content"] as? [[String: Any]] else { return nil }
            let text = blocks
                .compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return Message(
                role: role, text: text,
                timestamp: OmpSessionResolver.date(obj["timestamp"])
                    ?? OmpSessionResolver.date(message["timestamp"])
            )
        }
    }

    static func parseClaude(_ data: Data) -> [Message] {
        lines(data).compactMap { obj in
            guard let type = obj["type"] as? String, type == "user" || type == "assistant",
                  let message = obj["message"] as? [String: Any] else { return nil }
            let text: String
            if let content = message["content"] as? String {
                text = content
            } else if let blocks = message["content"] as? [[String: Any]] {
                text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
            } else {
                return nil
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("<"), !trimmed.hasPrefix("[Request interrupted") else { return nil }
            return Message(role: type, text: trimmed, timestamp: (obj["timestamp"] as? String).flatMap(parseDate))
        }
    }

    /// Codex rollout: event_msg의 user_message / agent_message.
    static func parseCodex(_ data: Data) -> [Message] {
        lines(data).compactMap { obj in
            guard let payload = obj["payload"] as? [String: Any], let type = payload["type"] as? String else { return nil }
            let role: String
            switch type {
            case "user_message": role = "user"
            case "agent_message": role = "assistant"
            default: return nil
            }
            guard let text = payload["message"] as? String else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return Message(role: role, text: trimmed, timestamp: (obj["timestamp"] as? String).flatMap(parseDate))
        }
    }

    /// `~/.codex/sessions/YYYY/MM/DD/rollout-<시각>-<id>.jsonl`. 날짜를 모르니 파일명 꼬리로 찾는다.
    static func codexRollout(sessionID: String, in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil,
                                                              options: [.skipsHiddenFiles]) else { return nil }
        let suffix = "-\(sessionID).jsonl"
        for case let file as URL in enumerator where file.lastPathComponent.hasSuffix(suffix)
            && !file.lastPathComponent.hasPrefix("._") {
            return file
        }
        return nil
    }

    private static func lines(_ data: Data) -> [[String: Any]] {
        data.split(separator: 10).compactMap { try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] }
    }

    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let integral = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    private static func parseDate(_ raw: String) -> Date? {
        (try? fractional.parse(raw)) ?? (try? integral.parse(raw))
    }
}

/// `fine keys`의 키 이름 → 바이트. tmux send-keys의 이름을 따른다 — 에이전트가 이미 아는 어휘라서.
enum ControlKeys {
    static let table: [String: String] = [
        "Enter": "\r", "Escape": "\u{1b}", "Tab": "\t", "BSpace": "\u{7f}", "Space": " ",
        "Up": "\u{1b}[A", "Down": "\u{1b}[B", "Right": "\u{1b}[C", "Left": "\u{1b}[D",
        "Home": "\u{1b}[H", "End": "\u{1b}[F", "PageUp": "\u{1b}[5~", "PageDown": "\u{1b}[6~", "Delete": "\u{1b}[3~",
    ]

    /// 알려진 이름, `C-x` 컨트롤 조합과 단일 문자만 허용한다. 오타를 입력으로 보내지 않는다.
    static func bytes(for name: String) -> Data? {
        if let known = table[name] { return Data(known.utf8) }
        if name.hasPrefix("C-"), name.count == 3, let scalar = name.last?.lowercased().unicodeScalars.first,
           (97...122).contains(scalar.value) {
            return Data([UInt8(scalar.value - 96)])
        }
        return name.count == 1 ? Data(name.utf8) : nil
    }
}
