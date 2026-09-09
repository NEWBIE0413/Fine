import XCTest
import SQLite3
@testable import Fine

final class QuickConversationScannerTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quick-conversations-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testLastAITitleWinsAndResultsSortByMtime() throws {
        let older = try writeTranscript([
            #"{"type":"user","message":{"content":"첫 질문"}}"#,
            #"{"type":"ai-title","aiTitle":"이전 제목"}"#,
            #"{"type":"ai-title","aiTitle":"최종 제목"}"#,
        ], modifiedAt: Date(timeIntervalSince1970: 100))
        let newer = try writeTranscript([
            #"{"type":"user","message":{"content":"새 대화"}}"#,
        ], modifiedAt: Date(timeIntervalSince1970: 200))

        let result = QuickConversationScanner.scan(directory: directory)
        XCTAssertEqual(result.map(\.id), [
            newer.deletingPathExtension().lastPathComponent,
            older.deletingPathExtension().lastPathComponent,
        ])
        XCTAssertEqual(result.map(\.title), ["새 대화", "최종 제목"])
    }

    func testFirstNonMetaUserMessageIsFallbackTitle() throws {
        _ = try writeTranscript([
            #"{"type":"user","message":{"content":"<command-name>/model</command-name>"}}"#,
            #"{"type":"user","message":{"content":"실제 첫 질문"}}"#,
            #"{"type":"user","message":{"content":"두 번째 질문"}}"#,
        ], modifiedAt: Date())

        XCTAssertEqual(
            QuickConversationScanner.scan(directory: directory).first?.title,
            "실제 첫 질문"
        )
    }

    func testSameNormalizedTitleKeepsNewestResumeFile() throws {
        _ = try writeTranscript([
            #"{"type":"ai-title","aiTitle":"같은   대화"}"#,
        ], modifiedAt: Date(timeIntervalSince1970: 100))
        let resumed = try writeTranscript([
            #"{"type":"ai-title","aiTitle":"같은 대화"}"#,
        ], modifiedAt: Date(timeIntervalSince1970: 300))

        let result = QuickConversationScanner.scan(directory: directory)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, resumed.deletingPathExtension().lastPathComponent)
    }

    func testAssistantModelsDoNotAffectLegacyConversationMetadata() throws {
        _ = try writeTranscript([
            #"{"type":"user","message":{"content":"공부 대화"}}"#,
            #"{"type":"assistant","message":{"model":"claude-codex-gpt-5.6-sol","role":"assistant"}}"#,
            #"{"type":"assistant","message":{"model":"claude-gemini-gemini-3.7-flash-high","role":"assistant"}}"#,
        ], modifiedAt: Date())

        let conversation = try XCTUnwrap(
            QuickConversationScanner.scan(directory: directory).first
        )
        XCTAssertEqual(conversation.title, "공부 대화")
    }

    func testRecentListMergesHarnessesByTimeAndKeepsEqualTitlesDistinct() throws {
        let store = try makeNativeStore()
        let codexID = UUID().uuidString.lowercased()
        try sql(store.codexDatabase, "INSERT INTO threads VALUES ('\(codexID)', '/tmp/fine', 'Same title', 'Codex summary', 200, 0, 'cli')")
        try sql(store.openCodeDatabase, "INSERT INTO session VALUES ('ses_MixedCase', '/tmp/fine', 'Same title', 300000, NULL, NULL)")
        let claude = try writeTranscript([#"{"type":"ai-title","aiTitle":"Same title"}"#], modifiedAt: Date(timeIntervalSince1970: 100))
        let result = QuickConversationScanner.scan(directory: directory, sessionStore: store, workingDirectory: "/tmp/fine")
        XCTAssertEqual(result.map(\.harness), [.opencode, .codex, .claude])
        XCTAssertEqual(result.map(\.title), ["Same title", "Codex summary", "Same title"])
        XCTAssertEqual(result.map(\.id), ["ses_MixedCase", codexID, claude.deletingPathExtension().lastPathComponent])
        XCTAssertEqual(result[0].modifiedAt.timeIntervalSince1970, 300)
        XCTAssertEqual(Set(result.map(\.listID)).count, 3)
    }

    func testRecentListExcludesOtherProjectsArchivedSubagentsAndMalformedIDs() throws {
        let store = try makeNativeStore()
        for (cwd, archived, source) in [("/tmp/other", 0, "cli"), ("/tmp/fine", 1, "cli"), ("/tmp/fine", 0, "subagent")] {
            try sql(store.codexDatabase, "INSERT INTO threads VALUES ('\(UUID().uuidString)', '\(cwd)', 'Title', '', 200, \(archived), '\(source)')")
        }
        try sql(store.codexDatabase, "INSERT INTO threads VALUES ('not-a-session', '/tmp/fine', 'Invalid', '', 200, 0, 'cli')")
        try sql(store.openCodeDatabase, """
            INSERT INTO session VALUES ('ses_other', '/tmp/other', 'Other', 200000, NULL, NULL);
            INSERT INTO session VALUES ('ses_child', '/tmp/fine', 'Child', 200000, 'ses_parent', NULL);
            INSERT INTO session VALUES ('ses_archived', '/tmp/fine', 'Archived', 200000, NULL, 300000);
            INSERT INTO session VALUES ('ses_empty', '/tmp/fine', 'New session - today', 200000, NULL, NULL);
            """)
        XCTAssertTrue(store.recentConversations(workingDirectory: "/tmp/fine").isEmpty)
    }

    func testMissingClaudeDirectoryDoesNotHideNativeConversationsAndOlderCodexSchemaWorks() throws {
        let store = try makeNativeStore()
        let codexID = UUID().uuidString
        try sql(store.codexDatabase, "ALTER TABLE threads DROP COLUMN name; INSERT INTO threads VALUES ('\(codexID)', '/tmp/fine', 'Older Codex', 10, 0, 'cli')")
        let result = QuickConversationScanner.scan(directory: directory.appendingPathComponent("missing"), sessionStore: store, workingDirectory: "/tmp/fine")
        XCTAssertEqual(result.map(\.title), ["Older Codex"])
        XCTAssertEqual(result.first?.harness, .codex)
    }

    func testLocalRecentSourcesWhenExplicitlyRequested() throws {
        guard ProcessInfo.processInfo.environment["FINE_RECENTS_LIVE"] == "1" else {
            throw XCTSkip("Set FINE_RECENTS_LIVE=1 for a read-only local integration check")
        }
        let rows = QuickConversationScanner.scan(
            directory: QuickConversationScanner.defaultTranscriptsDirectory(), sessionStore: .local
        )
        for harness in QuickHarness.allCases {
            let count = rows.filter { $0.harness == harness }.count
            print("Local recent source \(harness.rawValue): \(count) conversations")
            XCTAssertGreaterThan(count, 0, "Expected installed \(harness.title) conversations")
        }
    }

    func testNativePageFillsPastPlaceholderTitlesAndRespectsPerHarnessLimit() throws {
        let store = try makeNativeStore()
        for i in 0..<8 {
            let title = i > 3 ? "New session - today" : "Saved \(i)"
            try sql(store.openCodeDatabase, "INSERT INTO session VALUES ('ses_\(i)', '/tmp/fine', '\(title)', \(i * 1000), NULL, NULL)")
            try sql(store.codexDatabase, "INSERT INTO threads VALUES ('\(UUID().uuidString)', '/tmp/fine', '\(i > 3 ? "" : title)', '', \(i), 0, 'cli')")
        }
        let rows = store.recentConversations(workingDirectory: "/tmp/fine", limit: 2)
        XCTAssertEqual(rows.filter { $0.harness == .codex }.map(\.title), ["Saved 3", "Saved 2"])
        XCTAssertEqual(rows.filter { $0.harness == .opencode }.map(\.title), ["Saved 3", "Saved 2"])
    }

    private func makeNativeStore() throws -> HarnessSessionStore {
        let store = HarnessSessionStore(codexDatabase: directory.appendingPathComponent("codex.sqlite"), openCodeDatabase: directory.appendingPathComponent("opencode.db"))
        try sql(store.codexDatabase, "CREATE TABLE threads (id TEXT, cwd TEXT, title TEXT, name TEXT, updated_at INTEGER, archived INTEGER, source TEXT)")
        try sql(store.openCodeDatabase, "CREATE TABLE session (id TEXT, directory TEXT, title TEXT, time_updated INTEGER, parent_id TEXT, time_archived INTEGER)")
        return store
    }

    private func sql(_ url: URL, _ query: String) throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, query, nil, nil, nil), SQLITE_OK, String(cString: sqlite3_errmsg(db)))
    }

    private func writeTranscript(_ lines: [String], modifiedAt: Date) throws -> URL {
        let url = directory.appendingPathComponent("\(UUID().uuidString).jsonl")
        try (lines.joined(separator: "\n") + "\n").write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.modificationDate: modifiedAt],
            ofItemAtPath: url.path
        )
        return url
    }
}
