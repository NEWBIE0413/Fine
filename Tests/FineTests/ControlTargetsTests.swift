import XCTest
@testable import Fine

final class ControlTargetsTests: XCTestCase {
    private let windows = [
        ControlTargetResolver.WindowDescriptor(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!, isKey: false),
        ControlTargetResolver.WindowDescriptor(id: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!, isKey: true),
    ]
    private let tabs = [
        ControlTargetResolver.TabDescriptor(id: UUID(uuidString: "11111111-0000-0000-0000-000000000000")!, name: "새 대화 세션", conversationID: nil),
        ControlTargetResolver.TabDescriptor(id: UUID(uuidString: "22222222-0000-0000-0000-000000000000")!, name: "0", conversationID: "ses_AbC"),
        ControlTargetResolver.TabDescriptor(id: UUID(uuidString: "33333333-0000-0000-0000-000000000000")!, name: "Study", conversationID: "3F1E2D4C-0000-0000-0000-000000000000"),
    ]

    func testWindowQueryResolvesFrontIndexAndIdPrefix() {
        XCTAssertEqual(ControlTargetResolver.windowIndex(query: nil, in: windows), 1)
        XCTAssertEqual(ControlTargetResolver.windowIndex(query: "front", in: windows), 1)
        XCTAssertEqual(ControlTargetResolver.windowIndex(query: "0", in: windows), 0)
        XCTAssertEqual(ControlTargetResolver.windowIndex(query: "aaaa", in: windows), 0)
        XCTAssertEqual(ControlTargetResolver.windowIndex(query: "BBBBBBBB", in: windows), 1)
        XCTAssertNil(ControlTargetResolver.windowIndex(query: "2", in: windows))
        XCTAssertNil(ControlTargetResolver.windowIndex(query: "zzzz", in: windows))
        XCTAssertNil(ControlTargetResolver.windowIndex(query: nil, in: []))
        let noKey = windows.map { ControlTargetResolver.WindowDescriptor(id: $0.id, isKey: false) }
        XCTAssertEqual(ControlTargetResolver.windowIndex(query: nil, in: noKey), 0)
    }

    func testTabQueryPrefersNameAndSessionIdOverIndex() {
        XCTAssertEqual(ControlTargetResolver.tabIndex(query: "Study", in: tabs), 2)
        XCTAssertEqual(ControlTargetResolver.tabIndex(query: "study", in: tabs), 2)
        XCTAssertEqual(ControlTargetResolver.tabIndex(query: "0", in: tabs), 1, "a tab literally named \"0\" wins over index 0")
        XCTAssertEqual(ControlTargetResolver.tabIndex(query: "2", in: tabs), 2)
        XCTAssertEqual(ControlTargetResolver.tabIndex(query: "ses_AbC", in: tabs), 1)
        XCTAssertEqual(ControlTargetResolver.tabIndex(query: "3f1e2d4c-0000-0000-0000-000000000000", in: tabs), 2)
        XCTAssertEqual(ControlTargetResolver.tabIndex(query: "3333", in: tabs), 2)
        XCTAssertNil(ControlTargetResolver.tabIndex(query: "333", in: tabs), "id prefixes need at least 4 characters")
        XCTAssertNil(ControlTargetResolver.tabIndex(query: "", in: tabs))
        XCTAssertNil(ControlTargetResolver.tabIndex(query: "7", in: tabs))
    }

    func testMoveDestinationHandlesAbsoluteAndRelativeSpecs() {
        XCTAssertEqual(ControlTargetResolver.moveDestination(spec: "2", current: 0, count: 3), 2)
        XCTAssertEqual(ControlTargetResolver.moveDestination(spec: "+1", current: 0, count: 3), 1)
        XCTAssertEqual(ControlTargetResolver.moveDestination(spec: "-1", current: 2, count: 3), 1)
        XCTAssertNil(ControlTargetResolver.moveDestination(spec: "-1", current: 0, count: 3))
        XCTAssertNil(ControlTargetResolver.moveDestination(spec: "3", current: 0, count: 3))
        XCTAssertNil(ControlTargetResolver.moveDestination(spec: "up", current: 0, count: 3))
    }

    func testConfigurationKeepsBaseWhenHarnessMatchesAndResetsOtherwise() throws {
        let base = QuickSessionConfiguration(harness: .claude, modelID: "claude-opus-5", effort: .max, proxyEnabled: true)
        let same = try ControlArguments.configuration(base: base, harness: nil, model: nil, effort: "low", proxy: nil)
        XCTAssertEqual(same, QuickSessionConfiguration(harness: .claude, modelID: "claude-opus-5", effort: .low, proxyEnabled: true))

        let codex = try ControlArguments.configuration(base: base, harness: "Codex", model: "gpt-5.6", effort: nil, proxy: nil)
        XCTAssertEqual(codex, QuickSessionConfiguration(harness: .codex, modelID: "gpt-5.6", effort: .high, proxyEnabled: false))

        let reset = try ControlArguments.configuration(base: base, harness: nil, model: "default", effort: nil, proxy: nil)
        XCTAssertTrue(reset.isDefaultModel)

        XCTAssertThrowsError(try ControlArguments.configuration(base: base, harness: "gemini", model: nil, effort: nil, proxy: nil)) {
            XCTAssertEqual($0 as? ControlArgumentError, .invalidHarness("gemini"))
        }
        XCTAssertThrowsError(try ControlArguments.configuration(base: base, harness: nil, model: nil, effort: "turbo", proxy: nil)) {
            XCTAssertEqual($0 as? ControlArgumentError, .invalidEffort("turbo"))
        }
    }
}
