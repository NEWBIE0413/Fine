import AppKit
import SwiftUI

enum AppTermination {
    static var isTerminating = false
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag { NSApp.windows.first?.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        FineWindowRegistry.shared.persistWindowPresentations()
        AppTermination.isTerminating = true
        // 자식 정리를 여기서 동기적으로 끝낸다. .terminateNow 이후에는 비동기 승격이
        // 실행될 기회가 없어, 신호를 무시하는 자식이 launchd로 입양된 채 살아남는다.
        FineWindowRegistry.shared.cleanupAllSessions(synchronous: true)
        return .terminateNow
    }
}

@main
struct FineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "main", for: UUID.self) { $windowStateID in
            ContentView(windowStateID: $windowStateID)
                .frame(minWidth: 760, minHeight: 520)
        }
        .windowStyle(.hiddenTitleBar)
        .commands { FineCommands() }
    }
}

struct FineCommands: Commands {
    @FocusedObject private var appState: AppState?
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                openWindow(id: "main", value: UUID())
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Conversation") {
                appState?.addSession()
            }
            .keyboardShortcut("t", modifiers: .command)
        }

        CommandMenu("Conversation") {
            Button("Next Conversation") { appState?.selectNextSession() }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Conversation") { appState?.selectPreviousSession() }
                .keyboardShortcut("[", modifiers: [.command, .shift])
        }
    }
}

enum WindowRestorer {
    private static var didRun = false

    static func openRemainingWindowsIfNeeded(_ openWindow: OpenWindowAction) {
        guard !didRun else { return }
        didRun = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for state in WindowStateStorage.shared.unclaimedStates() {
                openWindow(id: "main", value: state.id)
            }
        }
    }
}
