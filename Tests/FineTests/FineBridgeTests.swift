import XCTest
@testable import Fine

final class FineBridgeTests: XCTestCase {
    func testExplicitHomeIsolationDoesNotDependOnShellHome() {
        let isolated = FinePaths.home(environment: ["FINE_HOME": "/tmp/fine-isolated", "HOME": "/wrong"])
        XCTAssertEqual(isolated.path, "/tmp/fine-isolated")
        XCTAssertEqual(FinePaths.home(environment: ["HOME": "/wrong"]), FileManager.default.homeDirectoryForCurrentUser)
        XCTAssertEqual(FinePaths.home(environment: ["FINE_HOME": "relative"]), FileManager.default.homeDirectoryForCurrentUser)
        XCTAssertEqual(FinePaths.codexHome(environment: ["FINE_HOME": "/tmp/fine-isolated"]).path, "/tmp/fine-isolated/.codex")
        XCTAssertEqual(FinePaths.codexHome(environment: ["FINE_HOME": "/tmp/fine-isolated", "CODEX_HOME": "/tmp/codex-custom"]).path, "/tmp/codex-custom")
    }

    func testRestoredTabGetsDifferentProcessFingerprint() {
        let id = UUID()
        let first = TerminalSession(id: id)
        let restored = TerminalSession(id: id)
        XCTAssertEqual(first.id, restored.id)
        XCTAssertNotEqual(first.controlFingerprint, restored.controlFingerprint)
        XCTAssertFalse(first.write(Data("must not report success before process start".utf8)))
    }

    func testSecondServerCannotReplaceFirstSocket() throws {
        let dir = URL(fileURLWithPath: "/tmp/fine-socket-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("control.sock").path
        let first = ControlServer(path: path) { _, done in done(.ok("first")) }
        let second = ControlServer(path: path) { _, done in done(.ok("second")) }
        try first.start()
        defer { first.stop() }
        let inode = try FileManager.default.attributesOfItem(atPath: path)[.systemFileNumber] as? NSNumber
        XCTAssertThrowsError(try second.start())
        second.stop()
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: path)[.systemFileNumber] as? NSNumber, inode)
    }

    func testServerDoesNotRemoveOrdinaryFile() throws {
        let dir = URL(fileURLWithPath: "/tmp/fine-file-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("control.sock")
        try Data("keep me".utf8).write(to: file)
        let server = ControlServer(path: file.path) { _, done in done(.ok("test")) }
        XCTAssertThrowsError(try server.start())
        server.stop()
        XCTAssertEqual(try Data(contentsOf: file), Data("keep me".utf8))
    }

    func testTranscriptLimitCannotCrashWithNegativeInput() {
        XCTAssertEqual(HarnessTranscript.messages(harness: .claude, sessionID: "missing", limit: -1), [])
    }
}
