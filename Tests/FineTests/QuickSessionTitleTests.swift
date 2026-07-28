import Combine
import XCTest
@testable import Fine

final class QuickSessionTitleTests: XCTestCase {
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
