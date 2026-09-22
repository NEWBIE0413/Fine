import SwiftUI

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding private var sceneWindowStateID: UUID?
    @StateObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @AppStorage("fineAppearance") private var appearance = FineAppearance.system.rawValue

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

            ZStack {
                if let session = appState.selectedSession {
                    AgentTerminalView(session: session)
                        .id(session.id)
                        .transition(.opacity)
                } else {
                    QuickHomeView()
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FineTheme.workspace)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: appState.selectedSession?.id)
        }
        .background(Color.clear)
        // 외형은 앱 전체에 한 번만 건다. 창 배경과 사이드바 재질이 같이 따라와야 한다.
        .preferredColorScheme((FineAppearance(rawValue: appearance) ?? .system).colorScheme)
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
            WindowOpener.register(openWindow)
            WindowRestorer.openRemainingWindowsIfNeeded(openWindow)
        }
    }
}
