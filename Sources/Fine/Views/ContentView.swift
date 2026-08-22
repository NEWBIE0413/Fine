import SwiftUI

struct ContentView: View {
    @Binding private var sceneWindowStateID: UUID?
    @StateObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    init(windowStateID: Binding<UUID?> = .constant(nil)) {
        _sceneWindowStateID = windowStateID
        _appState = StateObject(wrappedValue: AppState(
            requestedWindowStateID: windowStateID.wrappedValue
        ))
    }

    var body: some View {
        HStack(spacing: 0) {
            QuickSidebarView()
                .frame(width: FineTheme.sidebarWidth)

            Group {
                if let session = appState.selectedSession {
                    AgentTerminalView(session: session).id(session.id)
                } else {
                    QuickHomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FineTheme.workspace)
        }
        .background(Color.clear)
        .ignoresSafeArea(.container, edges: .top)
        .background {
            WindowBindingView(appState: appState, title: appState.windowTitle)
                .frame(width: 0, height: 0)
        }
        .environmentObject(appState)
        .focusedSceneObject(appState)
        .preferredColorScheme(.light)
        .onAppear {
            if sceneWindowStateID == nil {
                sceneWindowStateID = appState.windowStateID
            }
            QuickConversationScanner.shared.start()
            WindowRestorer.openRemainingWindowsIfNeeded(openWindow)
        }
    }
}
