import XCTest
@testable import Fine

final class QuickSessionConfigurationStorageTests: XCTestCase {
    private var directory: URL!
    private var stateFile: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quick-session-configurations-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        stateFile = directory.appendingPathComponent("state.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testConfigurationRoundTripsExactlyAndDoesNotOverwrite() {
        let sessionID = UUID().uuidString
        let original = QuickSessionConfiguration(
            modelID: "claude-codex-gpt-test[1m]",
            effort: .ultra,
            proxyEnabled: true
        )
        let storage = QuickSessionConfigurationStorage(stateFile: stateFile)

        storage.saveIfAbsent(original, for: sessionID)
        storage.saveIfAbsent(.default, for: sessionID)

        XCTAssertEqual(storage.configuration(for: sessionID), original)
        XCTAssertEqual(
            QuickSessionConfigurationStorage(stateFile: stateFile)
                .configuration(for: sessionID),
            original
        )
    }

    func testSessionsRemainIndependentAndMissingOrInvalidIDsReturnNil() {
        let firstID = UUID().uuidString
        let secondID = UUID().uuidString
        let storage = QuickSessionConfigurationStorage(stateFile: stateFile)
        let gemini = QuickSessionConfiguration(
            modelID: "claude-gemini-gemini-3.7-flash-high[1m]",
            effort: .high,
            proxyEnabled: false
        )

        storage.saveIfAbsent(gemini, for: firstID)
        storage.saveIfAbsent(.default, for: secondID)
        storage.saveIfAbsent(gemini, for: "not-a-uuid")

        XCTAssertEqual(storage.configuration(for: firstID), gemini)
        XCTAssertEqual(storage.configuration(for: secondID), .default)
        XCTAssertNil(storage.configuration(for: UUID().uuidString))
        XCTAssertNil(storage.configuration(for: "not-a-uuid"))
    }

    func testMalformedStateLoadsAsEmpty() throws {
        try Data("not json".utf8).write(to: stateFile)
        let storage = QuickSessionConfigurationStorage(stateFile: stateFile)

        XCTAssertNil(storage.configuration(for: UUID().uuidString))
    }
}
