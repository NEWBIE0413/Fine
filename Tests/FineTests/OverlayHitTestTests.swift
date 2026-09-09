import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import Fine

/// The model picker is an in-window overlay above an NSView-backed WKWebView.
/// SwiftUI must order it above that platform view, otherwise the scrim and the
/// card would render behind the terminal and never receive clicks.
final class OverlayHitTestTests: XCTestCase {
    @MainActor
    func testOverlayReceivesHitsAboveTheTerminalWebView() {
        let stateFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("fine-overlay-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: stateFile) }
        let state = AppState(storage: WindowStateStorage(stateFile: stateFile))
        let session = TerminalSession()
        state.sessions = [session]
        state.selectedSession = session
        defer { session.cleanup(force: true) }

        let hosting = NSHostingView(
            rootView: AgentTerminalView(session: session).environmentObject(state)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        settle(hosting)
        let center = NSPoint(x: 450, y: 320)
        let beforeHit = hosting.hitTest(center)
        XCTAssertTrue(
            containsWebView(beforeHit),
            "without the overlay the terminal web view should own the hit"
        )

        session.isModelPickerPresented = true
        settle(hosting)
        let hit = hosting.hitTest(center)
        XCTAssertNotNil(hit)
        XCTAssertFalse(
            containsWebView(hit),
            "overlay must sit above the terminal web view, got \(String(describing: hit))"
        )
    }

    @MainActor
    private func settle(_ view: NSView) {
        for _ in 0..<6 {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private func containsWebView(_ view: NSView?) -> Bool {
        var current = view
        while let candidate = current {
            if candidate is WKWebView || candidate is TerminalWebView || candidate is TerminalHostView {
                return true
            }
            current = candidate.superview
        }
        return false
    }
}
