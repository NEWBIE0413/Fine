import SwiftUI
import AppKit

/// Terminal view for a single session
struct AgentTerminalView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var session: TerminalSession

    var body: some View {
        if let error = session.startError {
            VStack(spacing: 12) {
                Text(error)
                    .foregroundColor(.secondary)
                Button("다시 시도") {
                    session.restartIfDead()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            SessionTerminalWrapper(session: session)
                .fineOverlay(isPresented: $session.isModelPickerPresented, alignment: .bottom) {
                    SessionModelPickerView(session: session)
                        .environmentObject(appState)
                }
        }
    }
}

private struct SessionModelPickerView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var session: TerminalSession
    @StateObject private var modelCatalog = QuickModelCatalog()
    @State private var selectedModelID: String
    @State private var selectedEffort: QuickEffort

    init(session: TerminalSession) {
        self.session = session
        _selectedModelID = State(initialValue: session.configuration.modelID)
        _selectedEffort = State(initialValue: session.configuration.effort)
    }

    private var selectedModel: QuickModelOption? {
        modelCatalog.models.first { $0.id == selectedModelID }
    }

    private var canRestart: Bool {
        session.configuration.harness != .opencode && session.resumableSessionID != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("모델 변경")
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            QuickModelPickerView(
                models: modelCatalog.models,
                selectedModelID: $selectedModelID,
                isPresented: .constant(true),
                dismissOnSelect: false,
                onRefresh: { modelCatalog.refresh(harness: session.configuration.harness) }
            )
            .clipShape(RoundedRectangle(cornerRadius: FineTheme.compactControlRadius))
            .overlay(
                RoundedRectangle(cornerRadius: FineTheme.compactControlRadius)
                    .stroke(FineTheme.divider, lineWidth: 1)
            )

            HStack(spacing: 10) {
                if let efforts = selectedModel?.supportedEfforts, !efforts.isEmpty {
                    Picker("Effort", selection: $selectedEffort) {
                        ForEach(efforts) { effort in
                            Text(effort.displayName).tag(effort)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                }
                Spacer(minLength: 0)
                Button("취소") {
                    session.isModelPickerPresented = false
                }
                .controlSize(.small)
                Button("이 모델로 재시작") {
                    let configuration = QuickSessionConfiguration(
                        harness: session.configuration.harness,
                        modelID: selectedModelID,
                        effort: selectedEffort,
                        proxyEnabled: session.configuration.proxyEnabled
                    )
                    session.isModelPickerPresented = false
                    // Let the overlay leave the hierarchy before the session,
                    // and with it the terminal view, is replaced underneath it.
                    DispatchQueue.main.async {
                        _ = appState.restartSession(session, with: configuration)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canRestart)
                .help(canRestart ? "같은 대화를 선택한 모델로 다시 시작합니다" : restartHelp)
            }
        }
        .padding(16)
        .onAppear {
            modelCatalog.refresh(harness: session.configuration.harness)
        }
        .onChange(of: selectedModelID) {
            guard let model = selectedModel,
                  !model.supportedEfforts.isEmpty,
                  !model.supportedEfforts.contains(selectedEffort) else { return }
            selectedEffort = model.supportedEfforts.contains(.high)
                ? .high
                : model.supportedEfforts.first ?? .high
        }
    }

    private var subtitle: String {
        switch session.configuration.harness {
        case .claude: return "같은 대화를 선택한 모델로 다시 시작합니다."
        case .codex: return "Codex 기본 설정으로 같은 대화를 다시 시작합니다."
        case .opencode: return "OpenCode 세션은 터미널처럼 /models 명령으로 전환합니다."
        }
    }

    private var restartHelp: String {
        switch session.configuration.harness {
        case .claude: return "Claude가 세션 ID를 만들기 전에는 재시작할 수 없습니다"
        case .codex: return "Codex가 세션 ID를 만들기 전에는 재시작할 수 없습니다"
        case .opencode: return "OpenCode 세션은 앱에서 재시작하지 않습니다"
        }
    }
}

/// 세션 소유 터미널 뷰를 SwiftUI에 안전하게 호스팅한다.
///
/// makeNSView는 매번 새 컨테이너(TerminalHostView)를 반환한다 — NavigationSplitView가
/// macOS에서 디테일 계층을 중복 인스턴스화해 유지하기 때문에, 세션의 단일 NSView를
/// 직접 반환하면 계층들끼리 뷰를 뺏고 결국 화면 밖 계층이 가져가 공백이 된다.
/// 대신 "윈도우에 실제로 붙어 있는" 컨테이너만 터미널 뷰를 인수(claim)한다.
struct SessionTerminalWrapper: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> TerminalHostView {
        let host = TerminalHostView()
        host.terminal = session.getOrCreateTerminal()
        host.attachIfNeeded()
        return host
    }

    func updateNSView(_ host: TerminalHostView, context: Context) {
        host.terminal = session.getOrCreateTerminal()
        host.attachIfNeeded()
        // 포커스는 실제 화면에 있는 계층에서만
        if host.window != nil {
            session.focusTerminal()
        }
    }
}

/// 터미널 뷰를 담는 컨테이너. 윈도우에 붙은 컨테이너만 터미널을 소유한다.
final class TerminalHostView: NSView {
    weak var terminal: TerminalWebView?

    func attachIfNeeded() {
        guard let terminal, window != nil else { return }
        guard terminal.superview !== self else { return }
        terminal.removeFromSuperview()
        terminal.translatesAutoresizingMaskIntoConstraints = false
        addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.topAnchor.constraint(equalTo: topAnchor),
            terminal.bottomAnchor.constraint(equalTo: bottomAnchor),
            terminal.leadingAnchor.constraint(equalTo: leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachIfNeeded()
    }

    override func layout() {
        super.layout()
        attachIfNeeded()
    }
}
