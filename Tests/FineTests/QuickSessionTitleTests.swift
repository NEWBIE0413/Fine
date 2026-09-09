import Combine
import SQLite3
import XCTest
@testable import Fine

final class QuickSessionTitleTests: XCTestCase {
    func testCodexIdentityParsesOpenRolloutPath() {
        let id = "66b557a0-8d77-4bb4-8816-913e80aac3ea"
        let output = "p123\nf46\nau\nn/Users/test/.codex/sessions/2026/09/09/rollout-2026-09-09T10-20-00-\(id).jsonl\n"
        XCTAssertEqual(CodexSessionResolver.sessionId(fromLsofOutput: output), id)
        XCTAssertNil(CodexSessionResolver.sessionId(fromLsofOutput: "n/tmp/rollout-\(id).jsonl"))
    }

    func testCodexIdentityRejectsReadOnlyAndAmbiguousRollouts() {
        let old = "66b557a0-8d77-4bb4-8816-913e80aac3ea"
        let new = "01a08539-e646-72a3-9d7d-1036add0f2d1"
        func record(_ id: String, access: String) -> String {
            "f46\na\(access)\nn/Users/test/.codex/sessions/2026/09/09/rollout-2026-09-09T10-20-00-\(id).jsonl\n"
        }
        XCTAssertNil(CodexSessionResolver.sessionId(fromLsofOutput: record(old, access: "r")))
        XCTAssertEqual(CodexSessionResolver.sessionId(fromLsofOutput:
            "p123\n" + record(old, access: "r") + "p124\n" + record(new, access: "u")), new)
        XCTAssertNil(CodexSessionResolver.sessionId(fromLsofOutput:
            record(old, access: "u") + record(new, access: "w")))
        XCTAssertEqual(CodexSessionResolver.sessionId(fromLsofOutput:
            record(new, access: "u") + record(new, access: "w")), new)
    }

    func testConfirmedCodexResumeSwitchUpdatesSnapshotAndNextLaunch() {
        let old = "66b557a0-8d77-4bb4-8816-913e80aac3ea"
        let new = "01a08539-e646-72a3-9d7d-1036add0f2d1"
        let session = TerminalSession(name: "Old", launch: .resume(sessionId: old),
                                      configuration: .defaultConfiguration(for: .codex))
        var writes = 0
        session.setPersistenceHandler { writes += 1 }
        session.applyMetadata(.init(id: new, title: "Latest"))
        XCTAssertEqual(session.resumableSessionID, old)
        session.applyMetadata(.init(id: new, title: "Latest"), confirmedCodexIdentity: new)
        XCTAssertEqual(session.snapshot().conversationID, new)
        XCTAssertEqual(session.name, "Latest")
        XCTAssertEqual(session.currentLaunch, .resume(sessionId: new))
        XCTAssertGreaterThan(writes, 0)
        session.applyMetadata(.init(id: old, title: "Stale"))
        XCTAssertEqual(session.resumableSessionID, new)
    }

    func testNativeStoresPreferCodexSummaryAndOpenCodeTitleAndRefresh() throws {
        let fixture = try metadataFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try executeSQL(fixture.store.codexDatabase, "INSERT INTO threads VALUES ('cx', '/tmp/cld', 1800000001, 0, 'cli', 'prompt', 'Long first message', '  Fine 제목 고치기  ')")
        try executeSQL(fixture.store.openCodeDatabase, "INSERT INTO session VALUES ('oc', '/tmp/cld', 1800000001000, NULL, NULL, 'OpenCode 요약')")
        XCTAssertEqual(fixture.store.metadata(harness: .codex, sessionID: "cx")?.title, "Fine 제목 고치기")
        XCTAssertEqual(fixture.store.metadata(harness: .opencode, sessionID: "oc")?.title, "OpenCode 요약")
        try executeSQL(fixture.store.codexDatabase, "UPDATE threads SET name = '최종 요약' WHERE id = 'cx'")
        XCTAssertEqual(fixture.store.metadata(harness: .codex, sessionID: "cx")?.title, "최종 요약")
        try executeSQL(fixture.store.codexDatabase, "UPDATE threads SET name = '' WHERE id = 'cx'")
        XCTAssertEqual(fixture.store.metadata(harness: .codex, sessionID: "cx")?.title, "Long first message")
        XCTAssertNil(fixture.store.metadata(harness: .codex, sessionID: "cx' OR 1=1 --"))
    }

    func testNewIdentityFiltersOldOtherDirectoryAndSubagentSessionsAndRejectsAmbiguity() throws {
        let fixture = try metadataFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        try executeSQL(fixture.store.codexDatabase, """
            INSERT INTO threads VALUES ('old', '/tmp/cld', 1799999990, 0, 'cli', 'prompt', '', '');
            INSERT INTO threads VALUES ('other', '/tmp/other', 1800000001, 0, 'cli', 'prompt', '', '');
            INSERT INTO threads VALUES ('sub', '/tmp/cld', 1800000001, 0, 'subagent', 'prompt', '', '');
            INSERT INTO threads VALUES ('cx', '/tmp/cld', 1800000001, 0, 'cli', 'prompt', '', '');
            """)
        XCTAssertEqual(fixture.store.newSessionID(harness: .codex, createdAfter: started, workingDirectory: "/tmp/cld", initialPrompt: "prompt"), "cx")
        try executeSQL(fixture.store.codexDatabase, "INSERT INTO threads VALUES ('collision', '/tmp/cld', 1800000002, 0, 'cli', 'prompt', '', '')")
        XCTAssertNil(fixture.store.newSessionID(harness: .codex, createdAfter: started, workingDirectory: "/tmp/cld", initialPrompt: "prompt"))
        try executeSQL(fixture.store.openCodeDatabase, """
            INSERT INTO session VALUES ('old', '/tmp/cld', 1799999990000, NULL, NULL, 'Old');
            INSERT INTO session VALUES ('child', '/tmp/cld', 1800000001000, 'parent', NULL, 'Child');
            INSERT INTO session VALUES ('other', '/tmp/other', 1800000001000, NULL, NULL, 'Other');
            INSERT INTO session VALUES ('oc', '/tmp/cld', 1800000001000, NULL, NULL, 'Summary');
            """)
        XCTAssertEqual(fixture.store.newSessionID(harness: .opencode, createdAfter: started, workingDirectory: "/tmp/cld", initialPrompt: nil), "oc")
        try executeSQL(fixture.store.openCodeDatabase, "INSERT INTO session VALUES ('collision', '/tmp/cld', 1800000002000, NULL, NULL, 'Other')")
        XCTAssertNil(fixture.store.newSessionID(harness: .opencode, createdAfter: started, workingDirectory: "/tmp/cld", initialPrompt: nil))
    }

    func testResumedCodexAndOpenCodeTitlesPersistAndIgnoreStaleOrEmptyUpdates() throws {
        for harness in [QuickHarness.codex, .opencode] {
            let session = TerminalSession(name: "fallback", launch: .resume(sessionId: "test"), configuration: .defaultConfiguration(for: harness))
            var writes = 0
            session.setPersistenceHandler { writes += 1 }
            session.applyMetadata(.init(id: "test", title: "대화 요약"))
            XCTAssertEqual(session.name, "대화 요약")
            XCTAssertEqual(session.snapshot().name, "대화 요약")
            session.applyMetadata(.init(id: "test", title: "대화 요약"))
            session.applyMetadata(.init(id: "test", title: "   "))
            session.applyMetadata(.init(id: "test", title: nil))
            session.applyMetadata(.init(id: "another-session", title: "Wrong title"))
            XCTAssertEqual(session.name, "대화 요약")
            XCTAssertEqual(writes, 1)
            session.applyMetadata(.init(id: "test", title: "갱신된 요약"))
            XCTAssertEqual(session.name, "갱신된 요약")
            XCTAssertEqual(writes, 2)
        }
    }

    func testMissingOrOlderDatabaseDoesNotCreateFilesOrLoseTitle() throws {
        let fixture = try metadataFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let missing = fixture.directory.appendingPathComponent("missing.sqlite")
        let store = HarnessSessionStore(codexDatabase: missing, openCodeDatabase: missing)
        XCTAssertNil(store.metadata(harness: .codex, sessionID: "test"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        try executeSQL(fixture.store.codexDatabase, "ALTER TABLE threads DROP COLUMN name; INSERT INTO threads VALUES ('old', '/tmp/cld', 1, 0, 'cli', 'prompt', 'Older Codex title')")
        XCTAssertEqual(fixture.store.metadata(harness: .codex, sessionID: "old")?.title, "Older Codex title")
        XCTAssertNil(HarnessSessionStore.displayTitle("New session - 2026-09-09T10:00:00Z"))
        XCTAssertNil(HarnessSessionStore.displayTitle(" \n "))
    }

    @MainActor
    func testBackgroundRefreshUpdatesResumedTitleOnMainThreadAndCleanupCancelsIt() throws {
        let fixture = try metadataFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try executeSQL(fixture.store.codexDatabase, "INSERT INTO threads VALUES ('cx', '/tmp/cld', 1, 0, 'cli', 'prompt', 'First message', '비동기 요약')")
        let session = TerminalSession(name: "fallback", launch: .resume(sessionId: "cx"), configuration: .defaultConfiguration(for: .codex))
        let updated = expectation(description: "title arrives on main thread")
        let subscription = session.$name.dropFirst().sink { title in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(title, "비동기 요약")
            updated.fulfill()
        }
        session.refreshSessionMetadata(processIdentifier: 0, store: fixture.store)
        wait(for: [updated], timeout: 2)
        withExtendedLifetime(subscription) {}
        XCTAssertEqual(session.name, "비동기 요약")

        let cancelled = TerminalSession(name: "fallback", launch: .resume(sessionId: "cx"), configuration: .defaultConfiguration(for: .codex))
        let unexpected = expectation(description: "cleaned up session must ignore queued result")
        unexpected.isInverted = true
        let cancellationSubscription = cancelled.$name.dropFirst().sink { _ in unexpected.fulfill() }
        cancelled.refreshSessionMetadata(processIdentifier: 0, store: fixture.store)
        cancelled.cleanup()
        wait(for: [unexpected], timeout: 0.2)
        withExtendedLifetime(cancellationSubscription) {}
    }

    func testLatestResumePinsTheStoredConversationBeforeLaunch() throws {
        let fixture = try metadataFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        try executeSQL(fixture.store.codexDatabase, """
            ALTER TABLE threads ADD COLUMN updated_at INTEGER;
            INSERT INTO threads VALUES ('old', '/tmp/cld', 1, 0, 'cli', '', '', '', 1);
            INSERT INTO threads VALUES ('recent', '/tmp/cld', 2, 0, 'cli', '', '', '', 10);
            INSERT INTO threads VALUES ('other', '/tmp/other', 3, 0, 'cli', '', '', '', 20);
            """)
        XCTAssertEqual(fixture.store.resolvingLatest(.resumeLatest, harness: .codex, workingDirectory: "/tmp/cld"), .resume(sessionId: "recent"))
        try executeSQL(fixture.store.openCodeDatabase, """
            ALTER TABLE session ADD COLUMN time_updated INTEGER;
            INSERT INTO session VALUES ('old', '/tmp/cld', 1, NULL, NULL, '', 1);
            INSERT INTO session VALUES ('recent', '/tmp/cld', 2, NULL, NULL, '', 10);
            INSERT INTO session VALUES ('child', '/tmp/cld', 3, 'recent', NULL, '', 20);
            """)
        XCTAssertEqual(fixture.store.resolvingLatest(.resumeLatest, harness: .opencode, workingDirectory: "/tmp/cld"), .resume(sessionId: "recent"))
        XCTAssertEqual(fixture.store.resolvingLatest(.resume(sessionId: "exact"), harness: .codex, workingDirectory: "/tmp/cld"), .resume(sessionId: "exact"))
        XCTAssertEqual(fixture.store.resolvingLatest(.blank, harness: .codex, workingDirectory: "/tmp/cld"), .blank)
    }

    private func metadataFixture() throws -> (directory: URL, store: HarnessSessionStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = HarnessSessionStore(codexDatabase: directory.appendingPathComponent("codex.sqlite"), openCodeDatabase: directory.appendingPathComponent("opencode.db"))
        try executeSQL(store.codexDatabase, "CREATE TABLE threads (id TEXT PRIMARY KEY, cwd TEXT, created_at INTEGER, archived INTEGER, source TEXT, first_user_message TEXT, title TEXT, name TEXT)")
        try executeSQL(store.openCodeDatabase, "CREATE TABLE session (id TEXT PRIMARY KEY, directory TEXT, time_created INTEGER, parent_id TEXT, time_archived INTEGER, title TEXT)")
        return (directory, store)
    }

    private func executeSQL(_ url: URL, _ sql: String) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        let result = sqlite3_exec(database, sql, nil, nil, nil)
        XCTAssertEqual(result, SQLITE_OK, String(cString: sqlite3_errmsg(database)))
    }

    private var cancellables: Set<AnyCancellable> = []

    func testSessionIdentityUsesPIDAndRejectsAnotherCwd() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pid: pid_t = 42_424
        let sessionId = UUID().uuidString.lowercased()
        try Data(#"{"pid":42424,"sessionId":"\#(sessionId)","cwd":"/tmp/cld","name":"ignore"}"#.utf8)
            .write(to: directory.appendingPathComponent("\(pid).json"))

        XCTAssertEqual(
            QuickSessionTitleResolver.sessionId(
                processIdentifier: pid,
                sessionsDirectory: directory,
                expectedWorkingDirectory: "/tmp/cld"
            ),
            sessionId
        )
        XCTAssertNil(QuickSessionTitleResolver.sessionId(
            processIdentifier: pid,
            sessionsDirectory: directory,
            expectedWorkingDirectory: "/tmp/other"
        ))
    }

    func testTitleRefreshUsesLastAITitleAndKeepsFallbackUntilAvailable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessionId = UUID().uuidString.lowercased()
        let transcript = directory.appendingPathComponent("\(sessionId).jsonl")
        try Data("""
        {"type":"user","message":{"content":"fallback prompt"}}
        {"type":"ai-title","aiTitle":"First title"}
        {"type":"ai-title","aiTitle":"Latest brief"}

        """.utf8).write(to: transcript)

        let session = TerminalSession(name: "fallback", launch: .resume(sessionId: sessionId))
        session.updateTitle(titlesBySessionId: [:])
        XCTAssertEqual(session.name, "fallback")
        session.updateTitle(titlesBySessionId: QuickConversationScanner.scanAITitles(directory: directory))
        XCTAssertEqual(session.name, "Latest brief")
    }

    func testSelectedSessionTitleChangeInvalidatesAppState() {
        let state = AppState()
        let session = TerminalSession()
        state.selectedSession = session
        let invalidated = expectation(description: "AppState forwards selected title")
        state.objectWillChange.sink { invalidated.fulfill() }.store(in: &cancellables)

        session.name = "Claude brief"

        wait(for: [invalidated], timeout: 1)
    }
}
