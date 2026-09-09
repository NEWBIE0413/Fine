import AppKit
import SwiftUI

/// Owns the entire padded row's mouse sequence. A SwiftUI Button consumes the
/// drag gesture, and transparent NSViews otherwise drag this window's background.
struct SessionRowInteraction: NSViewRepresentable {
    let item: OpenSessionDrag
    let title: String
    let onSelect: () -> Void
    let onDrop: (OpenSessionDrag, SessionInsertionEdge) -> Bool
    let onTarget: (SessionInsertionEdge?) -> Void

    func makeNSView(context: Context) -> SessionRowMouseView { SessionRowMouseView() }

    func updateNSView(_ view: SessionRowMouseView, context: Context) {
        view.item = item
        view.title = title
        view.onSelect = onSelect
        view.onDrop = onDrop
        view.onTarget = onTarget
        view.setAccessibilityLabel(title)
    }
}

class SessionRowMouseView: NSView, NSDraggingSource {
    static let pasteboardType = NSPasteboard.PasteboardType("com.fine.open-session")
    var item: OpenSessionDrag?
    var title = ""
    var onSelect: () -> Void = {}
    var onDrop: (OpenSessionDrag, SessionInsertionEdge) -> Bool = { _, _ in false }
    var onTarget: (SessionInsertionEdge?) -> Void = { _ in }
    private var mouseOrigin: NSPoint?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([Self.pasteboardType])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { nil }
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { onSelect() }
        else { super.keyDown(with: event) }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool { onSelect(); return true }

    override func mouseDown(with event: NSEvent) {
        mouseOrigin = convert(event.locationInWindow, from: nil)
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseOrigin != nil else { return }
        mouseOrigin = nil
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onSelect() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = mouseOrigin, let item else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - origin.x, point.y - origin.y) >= 4 else { return }
        mouseOrigin = nil
        let pasteboardItem = NSPasteboardItem()
        guard let data = try? JSONEncoder().encode(item) else { return }
        pasteboardItem.setData(data, forType: Self.pasteboardType)
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let preview = NSImage(size: bounds.size, flipped: false) { [title] rect in
            NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            (title as NSString).draw(in: rect.insetBy(dx: 10, dy: 8), withAttributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
            ])
            return true
        }
        draggingItem.setDraggingFrame(bounds, contents: preview)
        startDragging(draggingItem, event: event)
    }

    func startDragging(_ item: NSDraggingItem, event: NSEvent) {
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    func droppedItem(from pasteboard: NSPasteboard) -> OpenSessionDrag? {
        guard let data = pasteboard.data(forType: Self.pasteboardType),
              let incoming = try? JSONDecoder().decode(OpenSessionDrag.self, from: data),
              incoming.windowID == item?.windowID, incoming.sessionID != item?.sessionID else { return nil }
        return incoming
    }

    func insertionEdge(at point: NSPoint) -> SessionInsertionEdge {
        // AppKit coordinates increase upward unless the view is flipped.
        (isFlipped ? point.y < bounds.midY : point.y >= bounds.midY) ? .before : .after
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let valid = droppedItem(from: sender.draggingPasteboard) != nil
        onTarget(valid ? insertionEdge(at: convert(sender.draggingLocation, from: nil)) : nil)
        return valid ? .move : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if let event = NSEvent.mouseEvent(with: .leftMouseDragged, location: sender.draggingLocation,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { autoscroll(with: event) }
        return draggingEntered(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { onTarget(nil) }
    override func draggingEnded(_ sender: NSDraggingInfo) { onTarget(nil) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        droppedItem(from: sender.draggingPasteboard) != nil
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTarget(nil)
        guard let incoming = droppedItem(from: sender.draggingPasteboard) else { return false }
        return onDrop(incoming, insertionEdge(at: convert(sender.draggingLocation, from: nil)))
    }
}
