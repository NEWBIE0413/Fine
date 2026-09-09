import AppKit
import XCTest
@testable import Fine

@MainActor
final class SessionRowInteractionTests: XCTestCase {
    private final class DragProbe: SessionRowMouseView {
        var capturedDrag: NSDraggingItem?
        override func startDragging(_ item: NSDraggingItem, event: NSEvent) { capturedDrag = item }
    }

    private func event(_ type: NSEvent.EventType, _ point: NSPoint, window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                          windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                          clickCount: 1, pressure: 1)!
    }

    func testFullRowEdgesClickAndReleaseOutsideCancels() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 224, height: 37),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isMovableByWindowBackground = true
        let row = DragProbe(frame: NSRect(x: 0, y: 0, width: 224, height: 37))
        window.contentView = row
        var selections = 0
        row.onSelect = { selections += 1 }
        XCTAssertFalse(row.mouseDownCanMoveWindow)
        XCTAssertEqual(row.insertionEdge(at: NSPoint(x: 10, y: 36)), .before)
        XCTAssertEqual(row.insertionEdge(at: NSPoint(x: 10, y: 1)), .after)
        for point in [NSPoint(x: 1, y: 1), NSPoint(x: 223, y: 1), NSPoint(x: 223, y: 36), NSPoint(x: 110, y: 36)] {
            XCTAssertTrue(row.hitTest(point) === row)
            row.mouseDown(with: event(.leftMouseDown, point, window: window))
            row.mouseUp(with: event(.leftMouseUp, point, window: window))
        }
        XCTAssertEqual(selections, 4)
        row.mouseDown(with: event(.leftMouseDown, NSPoint(x: 10, y: 10), window: window))
        row.mouseUp(with: event(.leftMouseUp, NSPoint(x: 225, y: 10), window: window))
        XCTAssertEqual(selections, 4)
        XCTAssertTrue(row.accessibilityPerformPress())
        XCTAssertEqual(selections, 5)
    }

    func testNativeMouseDragCreatesPrivatePayloadWithoutSelectingAndRejectsOtherWindows() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 224, height: 37),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let row = DragProbe(frame: NSRect(x: 0, y: 0, width: 224, height: 37))
        window.contentView = row
        let item = OpenSessionDrag(windowID: UUID(), sessionID: UUID())
        row.item = item
        var selections = 0
        row.onSelect = { selections += 1 }
        row.mouseDown(with: event(.leftMouseDown, NSPoint(x: 100, y: 1), window: window))
        row.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: 102, y: 1), window: window))
        XCTAssertNil(row.capturedDrag)
        row.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: 100, y: 9), window: window))
        let drag = try XCTUnwrap(row.capturedDrag)
        XCTAssertEqual(drag.draggingFrame, row.bounds)
        row.mouseUp(with: event(.leftMouseUp, NSPoint(x: 100, y: 9), window: window))
        XCTAssertEqual(selections, 0)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(pasteboard.writeObjects([try XCTUnwrap(drag.item as? NSPasteboardItem)]))
        XCTAssertNil(row.droppedItem(from: pasteboard), "Reject a drop on itself")
        row.item = OpenSessionDrag(windowID: UUID(), sessionID: UUID())
        XCTAssertNil(row.droppedItem(from: pasteboard), "Reject a different window")
        row.item = OpenSessionDrag(windowID: item.windowID, sessionID: UUID())
        XCTAssertEqual(row.droppedItem(from: pasteboard)?.sessionID, item.sessionID)
        pasteboard.clearContents()
        pasteboard.setString("unrelated text", forType: .string)
        XCTAssertNil(row.droppedItem(from: pasteboard))
    }
}
