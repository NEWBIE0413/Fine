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
        HStack(spacing: 12) {
            QuickSidebarView()
                .frame(width: 240)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Group {
                if let session = appState.selectedSession {
                    AgentTerminalView(session: session).id(session.id)
                } else {
                    QuickHomeView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 4)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .padding(.top, 36)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
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
