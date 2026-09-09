import AppKit

enum AppResourcePolicy {
    static var hasVisibleWindows: Bool {
        NSApp?.windows.contains {
            $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible)
        } ?? false
    }
}
