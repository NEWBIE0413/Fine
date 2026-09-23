import SwiftUI

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding private var sceneWindowStateID: UUID?
    @StateObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @AppStorage("fineAppearance") private var appearance = FineAppearance.system.rawValue
    @AppStorage("sidebarWidth") private var sidebarWidth = Double(FineTheme.sidebarWidth)

    init(windowStateID: Binding<UUID?> = .constant(nil)) {
        _sceneWindowStateID = windowStateID
        _appState = StateObject(wrappedValue: AppState(
            requestedWindowStateID: windowStateID.wrappedValue
        ))
    }

    var body: some View {
        HStack(spacing: 0) {
            QuickSidebarView()
                .frame(width: sidebarWidth)
                // 손잡이는 레이아웃을 차지하지 않는다. 폭을 가진 요소로 두면
                // 사이드바와 작업부 사이에 그만큼 빈 띠가 생긴다.
                .overlay(alignment: .trailing) {
                    SidebarDivider(width: $sidebarWidth)
                        .offset(x: 5)
                }

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
        .overlay(ThemeTransitionOverlay(windowStateID: appState.windowStateID))
        .background(Color.clear)
        // 외형의 출처는 하나여야 한다. preferredColorScheme는 창에 외형을 직접 박는데,
        // NSApp/창에 건 값과 어긋나면 레이아웃이 한 번 돌 때마다 서로를 덮어쓴다
        // (실측: 적용 직후 DarkAqua → 잠시 뒤 Aqua로 복귀).
        // 그래서 SwiftUI에는 맡기지 않고 AppKit 쪽 한 곳에서만 건다.
        // 뷰들의 colorScheme 환경은 창의 실제 외형을 따라오므로 결과는 같다.
        .onChange(of: appearance) { _, value in
            FineAppearance.apply(FineAppearance(rawValue: value) ?? .system)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background {
            WindowBindingView(appState: appState, title: appState.windowTitle)
                .frame(width: 0, height: 0)
        }
        .environmentObject(appState)
        .focusedSceneObject(appState)
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
