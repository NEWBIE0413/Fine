import AppKit

final class FineWindowRegistry {
    static let shared = FineWindowRegistry()

    private final class Entry {
        weak var state: AppState?
        weak var window: NSWindow?

        init(state: AppState) { self.state = state }
    }

    private var entries: [Entry] = []
    private init() {}

    func register(_ state: AppState) {
        removeDeadEntries()
        guard !entries.contains(where: { $0.state === state }) else { return }
        entries.append(Entry(state: state))
    }

    func unregister(_ state: AppState) {
        entries.removeAll { $0.state == nil || $0.state === state }
    }

    func attach(window: NSWindow, to state: AppState) {
        register(state)
        entries.first(where: { $0.state === state })?.window = window
    }

    func detach(window: NSWindow, from state: AppState) {
        guard let entry = entries.first(where: { $0.state === state }),
              entry.window === window else { return }
        entry.window = nil
    }

    func persistWindowPresentations() {
        removeDeadEntries()
        for entry in entries {
            guard let state = entry.state, let window = entry.window else { continue }
            let isFullscreen = window.styleMask.contains(.fullScreen)
            let isZoomed = !isFullscreen && window.isZoomed
            let frame: WindowFrameState? = (isFullscreen || isZoomed) ? nil : .init(
                x: window.frame.origin.x,
                y: window.frame.origin.y,
                width: window.frame.width,
                height: window.frame.height
            )
            state.updateWindowPresentation(
                frame: frame,
                isZoomed: isZoomed,
                isFullscreen: isFullscreen
            )
        }
    }

    private func removeDeadEntries() {
        entries.removeAll { $0.state == nil }
    }
}
