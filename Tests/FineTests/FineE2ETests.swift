import XCTest
@testable import Fine

final class FineE2ETests: XCTestCase {
    /// Opt-in because it starts one real Claude conversation and consumes a small amount of usage.
    /// Run with `FINE_E2E=1 swift test --filter FineE2ETests`.
    @MainActor
    func testComposerTitleAndOpenConversationReuse() async throws {
        guard ProcessInfo.processInfo.environment["FINE_E2E"] == "1" else {
            throw XCTSkip("Set FINE_E2E=1 to run the live Claude flow")
        }
        guard FileManager.default.isExecutableFile(atPath: QuickSessionPolicy.ccvExecutablePath) else {
            XCTFail("ccv is not executable at \(QuickSessionPolicy.ccvExecutablePath)")
            return
        }

        let existingIDs = Set(QuickConversationScanner.scan(
            directory: QuickConversationScanner.defaultTranscriptsDirectory()
        ).map(\.id))
        let stateFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("FineE2E-\(UUID().uuidString).json")
        let state = AppState(storage: WindowStateStorage(stateFile: stateFile))
        defer {
            state.sessions.forEach { $0.cleanup(force: true) }
            try? FileManager.default.removeItem(at: stateFile)
        }

        state.addSession(
            initialPrompt: "Reply with exactly FINE_E2E_OK.",
            configuration: QuickSessionConfiguration(
                modelID: "claude-haiku-4-5",
                effort: .low,
                proxyEnabled: false
            )
        )
        let launched = try XCTUnwrap(state.selectedSession)

        let deadline = Date().addingTimeInterval(90)
        var conversation: QuickConversation?
        while Date() < deadline {
            let conversations = QuickConversationScanner.scan(
                directory: QuickConversationScanner.defaultTranscriptsDirectory()
            )
            conversation = conversations.first { !existingIDs.contains($0.id) }
            if launched.name != QuickSessionPolicy.initialSessionName,
               conversation?.aiTitle != nil {
                break
            }
            try await Task.sleep(for: .milliseconds(500))
        }

        let resumed = try XCTUnwrap(conversation, "Claude did not create a new transcript")
        XCTAssertNotNil(resumed.aiTitle)
        XCTAssertNotEqual(launched.name, QuickSessionPolicy.initialSessionName)

        state.resumeConversation(sessionId: resumed.id)

        XCTAssertIdentical(state.selectedSession, launched)
        XCTAssertEqual(state.sessions.count, 1)
    }
}
