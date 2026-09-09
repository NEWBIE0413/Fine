import AppKit
import SwiftUI

/// In-window presentation for Fine's pickers.
///
/// Fine used SwiftUI `.popover` here until two crash reports (2026-09-02,
/// 2026-09-03) showed the same abort: SwiftUI shows the NSPopover from inside
/// `NSHostingView.layout()`, AppKit adds it as a child window during that
/// layout pass, and a ViewBridge `NSRemoteView` observer throws while the
/// window ordering group is rebuilt. An overlay inside the existing window
/// never orders a new window, so that path cannot be reached at all.
extension View {
    func fineOverlay<Content: View>(
        isPresented: Binding<Bool>,
        alignment: Alignment = .center,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(FineOverlayPresentation(isPresented: isPresented, alignment: alignment, overlayContent: content))
    }
}

private struct FineOverlayPresentation<OverlayContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let alignment: Alignment
    let overlayContent: () -> OverlayContent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            ZStack {
                if isPresented {
                    FineOverlayContainer(isPresented: $isPresented, alignment: alignment, content: overlayContent)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isPresented)
        }
    }
}

private struct FineOverlayContainer<Content: View>: View {
    @Binding var isPresented: Bool
    let alignment: Alignment
    let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        ZStack(alignment: alignment) {
            FineTheme.overlayScrim
                .contentShape(Rectangle())
                .onTapGesture { isPresented = false }

            content()
                .background(
                    RoundedRectangle(cornerRadius: FineTheme.overlayCornerRadius, style: .continuous)
                        .fill(FineTheme.workspace)
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: FineTheme.overlayCornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: FineTheme.overlayCornerRadius, style: .continuous)
                        .stroke(FineTheme.glassEdge, lineWidth: 1)
                )
                .shadow(color: FineTheme.overlayShadow, radius: 22, y: 10)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.98)
                .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 1), value: appeared)
                .padding(24)
        }
        .onAppear { appeared = true }
        .background(EscapeKeyMonitor { isPresented = false })
        .transition(.opacity)
    }
}

/// Dismisses the overlay on Escape without stealing first responder from the
/// terminal or the composer: a local event monitor scoped to this window.
struct EscapeKeyMonitor: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onEscape = onEscape
    }

    static func dismantleNSView(_ view: MonitorView, coordinator: ()) {
        view.removeMonitor()
    }

    final class MonitorView: NSView {
        var onEscape: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                installMonitor()
            } else {
                removeMonitor()
            }
        }

        private func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.keyCode == 53, event.window === self.window else {
                    return event
                }
                DispatchQueue.main.async { self.onEscape?() }
                return nil
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit {
            removeMonitor()
        }
    }
}
