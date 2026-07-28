import AppKit
import SwiftUI

enum WindowIdentity {
    private static let prefix = "Fine.window."

    static func identifier(for stateID: UUID) -> NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(prefix + stateID.uuidString.lowercased())
    }

    static func frameAutosaveName(for stateID: UUID) -> NSWindow.FrameAutosaveName {
        NSWindow.FrameAutosaveName(prefix + stateID.uuidString.lowercased())
    }
}

enum WindowFrameRestoration {
    static func fittedFrame(
        _ saved: CGRect,
        visibleFrames: [CGRect],
        fallbackVisibleFrame: CGRect?,
        minimumSize: CGSize
    ) -> CGRect {
        guard !visibleFrames.isEmpty || fallbackVisibleFrame != nil else { return saved }
        let fallback = fallbackVisibleFrame ?? visibleFrames[0]
        let target = visibleFrames.max { lhs, rhs in
            intersectionArea(saved, lhs) < intersectionArea(saved, rhs)
        }.flatMap { intersectionArea(saved, $0) > 0 ? $0 : nil } ?? fallback
        let width = min(max(saved.width, minimumSize.width), target.width)
        let height = min(max(saved.height, minimumSize.height), target.height)
        let x = min(max(saved.minX, target.minX), target.maxX - width)
        let y = min(max(saved.minY, target.minY), target.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}

struct WindowBindingView: NSViewRepresentable {
    let appState: AppState
    let title: String

    func makeNSView(context: Context) -> WindowBindingNSView {
        WindowBindingNSView(appState: appState, title: title)
    }

    func updateNSView(_ view: WindowBindingNSView, context: Context) {
        view.update(appState: appState, title: title)
    }

    static func dismantleNSView(_ view: WindowBindingNSView, coordinator: ()) {
        view.detach()
    }
}

final class WindowBindingNSView: NSView {
    private weak var appState: AppState?
    private weak var boundWindow: NSWindow?
    private var title: String
    private var observers: [NSObjectProtocol] = []
    private var pendingSave: DispatchWorkItem?

    init(appState: AppState, title: String) {
        self.appState = appState
        self.title = title
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    func update(appState: AppState, title: String) {
        self.appState = appState
        self.title = title
        bindIfPossible()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        bindIfPossible()
    }

    func detach() {
        flushPresentation()
        removeObservers()
        if let boundWindow, let appState {
            FineWindowRegistry.shared.detach(window: boundWindow, from: appState)
        }
        boundWindow = nil
    }

    private func bindIfPossible() {
        guard let window, let appState else { return }
        if let boundWindow, boundWindow !== window { detach() }
        let isNewBinding = boundWindow !== window
        boundWindow = window
        if isNewBinding {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarSeparatorStyle = .none
            window.isMovableByWindowBackground = true
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.identifier = WindowIdentity.identifier(for: appState.windowStateID)
            window.setFrameAutosaveName(WindowIdentity.frameAutosaveName(for: appState.windowStateID))
            restorePresentation(window: window, appState: appState)
            installObservers(for: window)
        }
        window.title = title
        FineWindowRegistry.shared.attach(window: window, to: appState)
    }

    private func restorePresentation(window: NSWindow, appState: AppState) {
        if let saved = appState.restoredFrame {
            let fitted = WindowFrameRestoration.fittedFrame(
                CGRect(x: saved.x, y: saved.y, width: saved.width, height: saved.height),
                visibleFrames: NSScreen.screens.map(\.visibleFrame),
                fallbackVisibleFrame: NSScreen.main?.visibleFrame,
                minimumSize: CGSize(width: 760, height: 520)
            )
            if !window.styleMask.contains(.fullScreen) {
                window.setFrame(fitted, display: false)
            }
        }

        let wantsFullscreen = appState.restoredIsFullscreen
        let wantsZoom = appState.restoredIsZoomed && !wantsFullscreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak window] in
            guard let self, let window, self.boundWindow === window else { return }
            let isFullscreen = window.styleMask.contains(.fullScreen)
            if wantsFullscreen != isFullscreen {
                window.toggleFullScreen(nil)
            } else if !wantsFullscreen && wantsZoom != window.isZoomed {
                window.zoom(nil)
            }
        }
    }

    private func installObservers(for window: NSWindow) {
        removeObservers()
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
            NSWindow.didEndLiveResizeNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.scheduleSave()
            }
        }
    }

    private func removeObservers() {
        pendingSave?.cancel()
        pendingSave = nil
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers.removeAll()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.flushPresentation() }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    private func flushPresentation() {
        pendingSave?.cancel()
        pendingSave = nil
        guard let window = boundWindow, let appState else { return }
        let isFullscreen = window.styleMask.contains(.fullScreen)
        let isZoomed = !isFullscreen && window.isZoomed
        let frame: WindowFrameState? = (isFullscreen || isZoomed) ? nil : .init(
            x: window.frame.origin.x,
            y: window.frame.origin.y,
            width: window.frame.width,
            height: window.frame.height
        )
        appState.updateWindowPresentation(
            frame: frame,
            isZoomed: isZoomed,
            isFullscreen: isFullscreen
        )
    }
}
