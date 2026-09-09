import XCTest
@testable import Fine

final class SessionReorderingTests: XCTestCase {
    @MainActor
    func testMovesBothDirectionsPreservingInstancesSelectionAndSavedOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateFile = directory.appendingPathComponent("windows.json")
        let storage = WindowStateStorage(stateFile: stateFile)
        let configurations = QuickSessionConfigurationStorage(stateFile: directory.appendingPathComponent("config.json"))
        let windowID = UUID()
        let snapshots = QuickHarness.allCases.map {
            QuickSessionSnapshot(id: UUID(), name: $0.title, conversationID: nil,
                                 configuration: .defaultConfiguration(for: $0))
        }
        storage.update(WindowState(id: windowID, sessions: snapshots, selectedSessionID: snapshots[1].id))
        let state = AppState(requestedWindowStateID: windowID, storage: storage, configurationStorage: configurations)
        let original = state.sessions
        XCTAssertTrue(state.moveSession(id: original[0].id, to: original[2].id))
        XCTAssertEqual(state.sessions.map(\.id), [original[1].id, original[2].id, original[0].id])
        XCTAssertTrue(state.selectedSession === original[1])
        XCTAssertTrue(state.sessions[2] === original[0])
        XCTAssertFalse(state.sessions.contains(where: \.isRunning))
        XCTAssertTrue(state.moveSession(id: original[0].id, to: original[1].id))
        XCTAssertEqual(state.sessions.map(\.id), original.map(\.id))
        state.moveSession(id: original[2].id, by: -1)
        let reloaded = WindowStateStorage(stateFile: stateFile)
        let restored = AppState(requestedWindowStateID: windowID, storage: reloaded, configurationStorage: configurations)
        XCTAssertEqual(restored.sessions.map(\.id), [original[0].id, original[2].id, original[1].id])
        XCTAssertEqual(restored.selectedSession?.id, original[1].id)
        XCTAssertEqual(restored.sessions.map(\.configuration.harness), [.claude, .opencode, .codex])
        XCTAssertFalse(state.moveSession(id: UUID(), to: original[0].id))
        XCTAssertFalse(state.moveSession(id: original[0].id, to: UUID()))
        XCTAssertFalse(state.moveSession(id: original[0].id, to: original[0].id))
        state.moveSession(id: original[0].id, by: -1)
        XCTAssertEqual(state.sessions.map(\.id), restored.sessions.map(\.id))
    }
    @MainActor
    func testInsertionBoundariesPreserveNeighborsAndPersist() throws {
        let cases: [(Int, Int, SessionInsertionEdge, [Int])] = [
            (0, 2, .before, [1, 0, 2]),
            (0, 2, .after, [1, 2, 0]),
            (2, 0, .before, [2, 0, 1]),
            (2, 0, .after, [0, 2, 1]),
            (0, 1, .before, [0, 1, 2]),
            (2, 1, .after, [0, 1, 2]),
            (1, 1, .before, [0, 1, 2]),
            (1, 1, .after, [0, 1, 2]),
        ]
        for (source, target, edge, expected) in cases {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let stateFile = directory.appendingPathComponent("windows.json")
            let storage = WindowStateStorage(stateFile: stateFile)
            let configurations = QuickSessionConfigurationStorage(stateFile: directory.appendingPathComponent("config.json"))
            let windowID = UUID()
            let snapshots = QuickHarness.allCases.map {
                QuickSessionSnapshot(id: UUID(), name: $0.title, conversationID: nil,
                                     configuration: .defaultConfiguration(for: $0))
            }
            storage.update(WindowState(id: windowID, sessions: snapshots, selectedSessionID: snapshots[1].id))
            let state = AppState(requestedWindowStateID: windowID, storage: storage, configurationStorage: configurations)
            let original = state.sessions
            let moved = state.moveSession(id: original[source].id, relativeTo: original[target].id, edge: edge)
            XCTAssertEqual(moved, expected != [0, 1, 2])
            XCTAssertEqual(state.sessions.map(\.id), expected.map { original[$0].id })
            XCTAssertTrue(state.selectedSession === original[1])
            for (index, oldIndex) in expected.enumerated() { XCTAssertTrue(state.sessions[index] === original[oldIndex]) }
            let restored = AppState(requestedWindowStateID: windowID, storage: WindowStateStorage(stateFile: stateFile),
                                    configurationStorage: configurations)
            XCTAssertEqual(restored.sessions.map(\.id), state.sessions.map(\.id))
        }
    }

}
