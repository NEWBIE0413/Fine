import XCTest
import SQLite3
@testable import Fine

final class HarnessTranscriptTests: XCTestCase {
    func testClaudeTranscriptKeepsConversationTextOnly() {
        let data = Data([
            #"{"type":"user","timestamp":"2026-09-12T10:00:00.000Z","message":{"content":"버그 고쳐줘"}}"#,
            #"{"type":"user","message":{"content":"<command-name>/model</command-name>"}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","content":"x"}]}}"#,
            #"{"type":"assistant","timestamp":"2026-09-12T10:00:05Z","message":{"content":[{"type":"text","text":"고쳤어"},{"type":"tool_use","name":"Edit"}]}}"#,
            #"{"type":"progress","data":{}}"#,
        ].joined(separator: "\n").utf8)
        let messages = HarnessTranscript.parseClaude(data)
        XCTAssertEqual(messages.map(\.role), ["user", "assistant"])
        XCTAssertEqual(messages.map(\.text), ["버그 고쳐줘", "고쳤어"])
        XCTAssertEqual(messages[0].timestamp, ISO8601DateFormatter().date(from: "2026-09-12T10:00:00Z"))
        XCTAssertEqual(messages[1].timestamp, ISO8601DateFormatter().date(from: "2026-09-12T10:00:05Z"))
    }

    func testCodexRolloutUsesUserAndAgentMessages() throws {
        let data = Data([
            #"{"timestamp":"2026-09-12T11:00:00.000Z","type":"session_meta","payload":{"id":"abc","cwd":"/tmp"}}"#,
            #"{"timestamp":"2026-09-12T11:01:00.000Z","type":"event_msg","payload":{"type":"user_message","message":"Codex request"}}"#,
            #"{"timestamp":"2026-09-12T11:02:00.000Z","type":"event_msg","payload":{"type":"agent_message","message":"Done."}}"#,
            #"{"timestamp":"2026-09-12T11:03:00.000Z","type":"event_msg","payload":{"type":"task_complete"}}"#,
        ].joined(separator: "\n").utf8)
        XCTAssertEqual(HarnessTranscript.parseCodex(data).map { "\($0.role):\($0.text)" }, ["user:Codex request", "assistant:Done."])

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codex-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let day = root.appendingPathComponent("2026/09/12")
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        try data.write(to: day.appendingPathComponent("rollout-2026-09-12T11-00-00-abc.jsonl"))
        try Data("junk".utf8).write(to: day.appendingPathComponent("._rollout-2026-09-12T11-00-00-abc.jsonl"))
        XCTAssertEqual(HarnessTranscript.codexRollout(sessionID: "abc", in: root)?.lastPathComponent,
                       "rollout-2026-09-12T11-00-00-abc.jsonl")
        XCTAssertNil(HarnessTranscript.codexRollout(sessionID: "zzz", in: root))
        let limited = HarnessTranscript.messages(harness: .codex, sessionID: "abc", limit: 1, codexSessionsDirectory: root)
        XCTAssertEqual(limited?.map(\.text), ["Done."])
    }

    func testOpenCodeLimitCountsMessagesAndJoinsTextParts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("fine-transcript-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("opencode.db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(file.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
            CREATE TABLE message (id TEXT, session_id TEXT, time_created INTEGER, data TEXT);
            CREATE TABLE part (id TEXT, session_id TEXT, message_id TEXT, time_created INTEGER, data TEXT);
            INSERT INTO message VALUES ('m1','s',1000,'{"role":"user"}'),('m2','s',2000,'{"role":"assistant"}'),('m3','s',3000,'{"role":"assistant"}');
            INSERT INTO part VALUES ('p1','s','m1',1000,'{"type":"text","text":"question"}'),('p2','s','m2',2000,'{"type":"text","text":"one"}'),('p3','s','m2',2100,'{"type":"tool","text":"skip"}'),('p4','s','m2',2200,'{"type":"text","text":"two"}'),('p5','s','m3',3000,'{"type":"text","text":"three"}');
            """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        let store = HarnessSessionStore(codexDatabase: root.appendingPathComponent("missing"), openCodeDatabase: file)
        XCTAssertEqual(store.openCodeMessages(sessionID: "s", limit: 2).map(\.text), ["one\ntwo", "three"])
        XCTAssertEqual(store.openCodeMessages(sessionID: "missing", limit: 2), [])
        XCTAssertEqual(store.openCodeMessages(sessionID: "s", limit: -1), [])
    }

    func testKeyNamesFollowTmuxVocabulary() {
        XCTAssertEqual(ControlKeys.bytes(for: "Enter"), Data("\r".utf8))
        XCTAssertEqual(ControlKeys.bytes(for: "C-c"), Data([3]))
        XCTAssertEqual(ControlKeys.bytes(for: "C-Z"), Data([26]))
        XCTAssertEqual(ControlKeys.bytes(for: "Up"), Data("\u{1b}[A".utf8))
        XCTAssertNil(ControlKeys.bytes(for: "Enetr"))
        XCTAssertEqual(ControlKeys.bytes(for: "x"), Data("x".utf8))
        XCTAssertNil(ControlKeys.bytes(for: ""))
    }
}
