import XCTest
@testable import Fine

final class WindowStateStorageTests: XCTestCase {
    func testRoundtripIncludesFrameAndPresentationFlags() throws {
        let state = WindowState(
            id: UUID(),
            frame: WindowFrameState(x: 100, y: 80, width: 900, height: 600),
            isZoomed: true,
            isFullscreen: false
        )
        let decoded = try JSONDecoder().decode(
            WindowState.self,
            from: JSONEncoder().encode(state)
        )
        XCTAssertEqual(decoded, state)
        XCTAssertTrue(decoded.resolvedIsZoomed)
        XCTAssertFalse(decoded.resolvedIsFullscreen)
    }

    func testLegacyStateDefaultsPresentationFlags() throws {
        let id = UUID()
        let state = try JSONDecoder().decode(
            WindowState.self,
            from: Data(#"{"id":"\#(id.uuidString)"}"#.utf8)
        )
        XCTAssertNil(state.frame)
        XCTAssertFalse(state.resolvedIsZoomed)
        XCTAssertFalse(state.resolvedIsFullscreen)
    }

    func testExactClaimIgnoresSavedArrayOrder() throws {
        let first = WindowState(id: UUID(), frame: nil, isZoomed: nil, isFullscreen: nil)
        let target = WindowState(id: UUID(), frame: nil, isZoomed: nil, isFullscreen: nil)
        XCTAssertEqual(
            WindowStateStorage.exactUnclaimedState(
                id: target.id,
                states: [first, target],
                claimedIDs: []
            ),
            target
        )
        XCTAssertNil(WindowStateStorage.exactUnclaimedState(
            id: target.id,
            states: [first, target],
            claimedIDs: [target.id]
        ))
    }
}
