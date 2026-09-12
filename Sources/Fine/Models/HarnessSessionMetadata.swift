import Foundation
import SQLite3

struct HarnessSessionMetadata: Equatable {
    let id: String
    let title: String?
}

/// Read harness metadata and, for explicit transcript requests, conversation text.
/// SQLite connections are short-lived and read-only, with a bounded busy wait.
struct HarnessSessionStore {
    let codexDatabase: URL
    let openCodeDatabase: URL

    static var local: Self {
        let home = FinePaths.home
        let environment = ProcessInfo.processInfo.environment
        let codexHome = FinePaths.codexHome(environment: environment)
        let databases = (try? FileManager.default.contentsOfDirectory(
            at: codexHome, includingPropertiesForKeys: nil
        )) ?? []
        let codexDatabase = databases.filter {
            $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite"
        }.max {
            $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending
        } ?? codexHome.appendingPathComponent("state_5.sqlite")
        let dataHome = environment["XDG_DATA_HOME"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".local/share")
        return Self(
            codexDatabase: codexDatabase,
            openCodeDatabase: dataHome.appendingPathComponent("opencode/opencode.db")
        )
    }

    func metadata(harness: QuickHarness, sessionID: String) -> HarnessSessionMetadata? {
        guard harness != .claude else { return nil }
        let database = harness == .codex ? codexDatabase : openCodeDatabase
        let query = harness == .codex
            ? "SELECT id, COALESCE(NULLIF(trim(name), ''), title) AS title FROM threads WHERE id = ?"
            : "SELECT id, title FROM session WHERE id = ?"
        // Older Codex databases predate `name`. Their title remains a useful fallback.
        let rows = read(database, query: query, arguments: [sessionID])
            ?? (harness == .codex
                ? read(database, query: "SELECT id, title FROM threads WHERE id = ?", arguments: [sessionID])
                : nil)
        guard let row = rows?.first, let id = row["id"] else { return nil }
        return HarnessSessionMetadata(id: id, title: Self.displayTitle(row["title"]))
    }

    func newSessionID(
        harness: QuickHarness, createdAfter: Date, workingDirectory: String,
        initialPrompt: String?
    ) -> String? {
        guard harness != .claude else { return nil }
        let query: String
        var arguments: [String]
        if harness == .codex {
            query = """
                SELECT id FROM threads
                WHERE cwd = ? AND created_at >= ? AND archived = 0 AND source = 'cli'
                """ + (initialPrompt == nil ? "" : " AND first_user_message = ?") + " LIMIT 2"
            arguments = [workingDirectory, String(Int(createdAfter.timeIntervalSince1970))]
            if let initialPrompt { arguments.append(initialPrompt) }
        } else {
            query = """
                SELECT id FROM session
                WHERE directory = ? AND time_created >= ? AND parent_id IS NULL
                AND time_archived IS NULL LIMIT 2
                """
            arguments = [workingDirectory, String(Int(createdAfter.timeIntervalSince1970 * 1_000))]
        }
        let database = harness == .codex ? codexDatabase : openCodeDatabase
        guard let rows = read(database, query: query, arguments: arguments), rows.count == 1 else {
            // Never attach an arbitrary "latest" thread when simultaneous launches
            // are ambiguous. Keep the fallback label instead of resuming another chat.
            return nil
        }
        return rows[0]["id"]
    }

    func recentConversations(workingDirectory: String, limit: Int = 200) -> [QuickConversation] {
        let filter = "FROM threads WHERE cwd = ? AND archived = 0 AND source = 'cli' "
        // Stop the read-only cursor after enough *displayable* rows. Blank or
        // placeholder titles must not hide valid older conversations behind a page.
        let codex = read(codexDatabase, query:
            "SELECT id, COALESCE(NULLIF(trim(name), ''), title) AS title, updated_at AS updated "
            + filter + "ORDER BY updated_at DESC, id DESC", arguments: [workingDirectory],
                         maximumRows: limit, accepting: { Self.conversation($0, harness: .codex) != nil })
            ?? read(codexDatabase, query: "SELECT id, title, updated_at AS updated "
                + filter + "ORDER BY updated_at DESC, id DESC", arguments: [workingDirectory],
                    maximumRows: limit, accepting: { Self.conversation($0, harness: .codex) != nil })
            ?? []
        let openCode = read(openCodeDatabase, query: """
            SELECT id, title, time_updated AS updated FROM session
            WHERE directory = ? AND parent_id IS NULL AND time_archived IS NULL
            ORDER BY time_updated DESC, id DESC
            """, arguments: [workingDirectory], maximumRows: limit,
                            accepting: { Self.conversation($0, harness: .opencode) != nil }) ?? []
        return codex.compactMap { Self.conversation($0, harness: .codex) }
            + openCode.compactMap { Self.conversation($0, harness: .opencode) }
    }

    private static func conversation(_ row: [String: String], harness: QuickHarness) -> QuickConversation? {
        guard let id = row["id"], QuickSessionIdentifier.isValid(id, for: harness),
              let title = displayTitle(row["title"]),
              let updated = row["updated"].flatMap(Double.init), updated.isFinite else { return nil }
        return QuickConversation(
            id: id, title: title, aiTitle: title,
            modifiedAt: Date(timeIntervalSince1970: harness == .opencode ? updated / 1_000 : updated),
            transcriptURL: nil, harness: harness
        )
    }

    func resolvingLatest(_ launch: QuickLaunch, harness: QuickHarness, workingDirectory: String) -> QuickLaunch {
        guard case .resumeLatest = launch, harness != .claude else { return launch }
        let rows: [[String: String]]?
        if harness == .codex {
            let base = "SELECT id FROM threads WHERE cwd = ? AND archived = 0 AND source = 'cli' "
            rows = read(codexDatabase, query: base + "ORDER BY recency_at_ms DESC, id DESC LIMIT 1", arguments: [workingDirectory])
                ?? read(codexDatabase, query: base + "ORDER BY updated_at DESC, id DESC LIMIT 1", arguments: [workingDirectory])
        } else {
            rows = read(openCodeDatabase, query: """
                SELECT id FROM session WHERE directory = ? AND parent_id IS NULL
                AND time_archived IS NULL ORDER BY time_updated DESC, id DESC LIMIT 1
                """, arguments: [workingDirectory])
        }
        guard let id = rows?.first?["id"] else { return launch }
        return .resume(sessionId: id)
    }

    static func displayTitle(_ title: String?) -> String? {
        guard let title else { return nil }
        let value = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !value.isEmpty, !value.hasPrefix("New session - ") else { return nil }
        return String(value.prefix(120))
    }

    /// OpenCode 대화 본문. message.data의 role과 part.data의 text 파트를 시간순으로 합친다.
    /// `fine transcript`용 — 로컬 스토어를 읽기 전용으로 여는 기존 규칙을 그대로 따른다.
    func openCodeMessages(sessionID: String, limit: Int) -> [HarnessTranscript.Message] {
        let limit = min(500, max(0, limit))
        guard limit > 0 else { return [] }
        let rows = read(openCodeDatabase, query: """
            SELECT m.id AS message_id, m.data AS message, p.data AS part, m.time_created AS created
            FROM part p JOIN message m ON m.id = p.message_id
            WHERE m.id IN (
                SELECT m2.id FROM message m2
                WHERE m2.session_id = ? AND json_extract(m2.data, '$.role') IN ('user', 'assistant')
                AND EXISTS (SELECT 1 FROM part p2 WHERE p2.message_id = m2.id AND json_extract(p2.data, '$.type') = 'text')
                ORDER BY m2.time_created DESC LIMIT ?
            ) AND json_extract(p.data, '$.type') = 'text'
            ORDER BY m.time_created DESC, p.time_created ASC
            """, arguments: [sessionID, String(limit)]) ?? []
        var order: [String] = []
        var messages: [String: HarnessTranscript.Message] = [:]
        for row in rows {
            guard let id = row["message_id"],
                  let message = row["message"].flatMap({ try? JSONSerialization.jsonObject(with: Data($0.utf8)) }) as? [String: Any],
                  let part = row["part"].flatMap({ try? JSONSerialization.jsonObject(with: Data($0.utf8)) }) as? [String: Any],
                  let text = part["text"] as? String,
                  let role = message["role"] as? String,
                  let created = row["created"].flatMap(Double.init) else { continue }
            let previous = messages[id]
            if previous == nil { order.append(id) }
            messages[id] = .init(role: role, text: previous.map { $0.text + "\n" + text } ?? text,
                                 timestamp: Date(timeIntervalSince1970: created / 1_000))
        }
        return order.reversed().compactMap { messages[$0] }
    }

    private func read(_ url: URL, query: String, arguments: [String], maximumRows: Int = .max,
                      accepting: ([String: String]) -> Bool = { _ in true }) -> [[String: String]]? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            return nil
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 100)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        for (index, argument) in arguments.enumerated() {
            let result = argument.withCString {
                sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            guard result == SQLITE_OK else { return nil }
        }
        var rows: [[String: String]] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                var row: [String: String] = [:]
                for column in 0..<sqlite3_column_count(statement) {
                    if let name = sqlite3_column_name(statement, column),
                       let value = sqlite3_column_text(statement, column) {
                        row[String(cString: name)] = String(cString: value)
                    }
                }
                if accepting(row) { rows.append(row) }
                if rows.count >= max(1, maximumRows) { return rows }
            case SQLITE_DONE: return rows
            default: return nil
            }
        }
    }
}
