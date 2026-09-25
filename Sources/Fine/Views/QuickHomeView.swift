import SwiftUI

struct QuickHomeView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var modelCatalog = QuickModelCatalog()
    @State private var prompt = ""
    @State private var harness: QuickHarness
    @State private var selectedModelID: String
    @State private var selectedEffort: QuickEffort
    @State private var proxyEnabled: Bool
    @State private var isModelPickerPresented = false
    /// 돋보기 모드: 입력을 새 대화가 아니라 "찾을 대화의 설명"으로 받는다.
    @State private var isFinding = false
    @State private var findStatus = QuickFindStatus.idle
    /// 돋보기를 누를 때마다 하나씩 늘어 입력창 테두리를 한 번 빛나게 한다.
    @State private var composerFlash = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameter finding: 돋보기 모드로 시작한다.
    init(finding: Bool = false) {
        _isFinding = State(initialValue: finding)
        let saved = QuickComposerPreferences.load()
        _harness = State(initialValue: saved.harness)
        _selectedModelID = State(initialValue: saved.modelID)
        _selectedEffort = State(initialValue: saved.effort)
        _proxyEnabled = State(initialValue: saved.proxyEnabled)
    }

    var body: some View {
        QuickHomePresentation(openTabs: appState.sessions.map(\.name)) {
            VStack(spacing: 14) {
                QuickHomeComposer(
                    prompt: $prompt,
                    placeholder: isFinding ? "찾을 대화를 설명하세요 — 예: zeb 브라우저 만든 세션" : "무엇이든 물어보세요",
                    accessibilityName: isFinding ? "찾을 대화 설명" : "새 대화 메시지",
                    flash: composerFlash,
                    onSubmit: submit
                ) {
                    composerControls
                }
                belowComposer
            }
        }
        .fineOverlay(isPresented: $isModelPickerPresented) {
            QuickModelPickerView(
                models: modelCatalog.models,
                selectedModelID: $selectedModelID,
                isPresented: $isModelPickerPresented,
                onRefresh: { modelCatalog.refresh(harness: harness) },
                selectedEffort: $selectedEffort,
                isLoading: modelCatalog.isLoading
            )
        }
        .onAppear {
            modelCatalog.refresh(harness: harness)
        }
        .task(id: harness) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(180))
                guard !Task.isCancelled else { return }
                if AppResourcePolicy.hasVisibleWindows { modelCatalog.refresh(harness: harness) }
            }
        }
        .onChange(of: harness) { _, newHarness in
            selectedModelID = QuickModelOption.defaultID
            proxyEnabled = false
            modelCatalog.refresh(harness: newHarness)
            persistSelection()
        }
        .onChange(of: selectedModelID) { _, _ in
            if selectedModel.requiresProxy {
                proxyEnabled = true
            } else if selectedModel.isDefault {
                proxyEnabled = false
            }
            constrainSelectedEffort()
            persistSelection()
        }
        .onChange(of: prompt) {
            // 못 찾은 뒤 설명을 고치기 시작하면 지난 결과는 치운다.
            if findStatus.isSettled { animateFind { findStatus = .idle } }
        }
        .task(id: findStatus) {
            // 결과만 남은 막대는 읽을 시간을 준 뒤 저절로 접힌다.
            guard findStatus.isSettled else { return }
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            animateFind { findStatus = .idle }
        }
        .onChange(of: selectedEffort) { persistSelection() }
        .onChange(of: proxyEnabled) { persistSelection() }
        .onChange(of: modelCatalog.models) { _, models in
            guard modelCatalog.harness == harness else { return }
            let resolved = QuickComposerPreferences.resolved(
                currentConfiguration,
                availableModels: models
            )
            selectedModelID = resolved.modelID
            selectedEffort = resolved.effort
            proxyEnabled = resolved.proxyEnabled
            QuickComposerPreferences.save(resolved)
        }
    }

    private var composerControls: some View {
        QuickHomeControls {
            if isFinding { findModePill } else { harnessPicker }
        } options: {
            // 찾기는 Haiku로 정해져 있다. 모델을 고를 이유가 없다.
            if !isFinding { modelOptions }
        } send: {
            HStack(spacing: 6) {
                if !isFinding { findToggle }
                sendButton
            }
        }
    }

    /// 새 대화 줄에서 돋보기 모드로 들어가는 문.
    private var findToggle: some View {
        Button { setFinding(true) } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: FineTheme.compactControlHeight, height: FineTheme.compactControlHeight)
                .background(
                    RoundedRectangle(cornerRadius: FineTheme.compactControlRadius, style: .continuous)
                        .fill(FineTheme.controlFill)
                )
        }
        .buttonStyle(.finePress)
        .keyboardShortcut("f", modifiers: .command)
        .help("찾기 — 설명으로 예전 대화를 찾아 엽니다 (⌘F)")
        .accessibilityLabel("대화 찾기")
    }

    /// 찾기 모드임을 알리고, 누르면 새 대화로 돌아간다.
    private var findModePill: some View {
        Button { setFinding(false) } label: {
            FineControlPill(title: "찾기 · Haiku", trailingSymbol: "xmark") {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .buttonStyle(.finePress)
        .fixedSize()
        .keyboardShortcut("f", modifiers: .command)
        .disabled(findStatus.isBusy)
        .help("새 대화로 돌아가기 (⌘F)")
        .accessibilityLabel("찾기 끝내기")
    }

    private func setFinding(_ on: Bool) {
        animateFind {
            isFinding = on
            findStatus = .idle
        }
        if on { composerFlash += 1 }
    }

    private func animateFind(_ change: () -> Void) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.9), change)
    }

    /// 입력창 아래 한 줄. 평소에는 안내 문구이고, 찾는 동안에는 작업 막대로 바뀐다.
    private var belowComposer: some View {
        ZStack(alignment: .top) {
            if findStatus == .idle {
                Text(isFinding ? findIdleDescription : sessionModeDescription)
                    .font(.system(size: 11))
                    .fineTracking(11)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .transition(.opacity)
            } else {
                FindTaskBar(status: findStatus) { animateFind { findStatus = .idle } }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -8))
                            .combined(with: .scale(scale: 0.97, anchor: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                    ))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var findIdleDescription: String {
        "Haiku가 최근 대화 \(SessionFinder.candidateLimit)개에서 골라 엽니다 · 열린 탭이면 그 탭으로 갑니다"
    }

    private func find(_ query: String) {
        guard !findStatus.isBusy else { return }
        let started = Date()
        animateFind { findStatus = .gathering(query: query, since: started) }
        SessionFinder.find(query, from: appState, open: false, progress: { count in
            animateFind { findStatus = .asking(query: query, count: count, since: started) }
        }) { outcome in
            switch outcome {
            case .found(let candidate, _):
                animateFind { findStatus = .found(title: candidate.conversation.title, wasOpen: candidate.isOpen) }
                // 찾은 것을 한 박자 보여 주고, 막대를 거둔 뒤에 연다. 탭이 열리면 이 화면은 내려가므로
                // 먼저 열어 버리면 막대가 접히지 못하고 화면째 사라진다.
                let beat = reduceMotion ? 0 : 0.75
                DispatchQueue.main.asyncAfter(deadline: .now() + beat) {
                    animateFind { findStatus = .idle }
                    DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.3)) {
                        isFinding = false
                        prompt = ""
                        SessionFinder.open(candidate.conversation, from: appState)
                    }
                }
            case .notFound(let reason):
                animateFind { findStatus = .notFound(query: query, reason: reason) }
            case .failed(let message):
                animateFind { findStatus = .failed(query: query, message: message) }
            }
        }
    }

    /// 모델과 깊이를 한 줄에 함께 보여준다. 둘은 늘 같이 정해지는 값이다.
    private var modelPickerTitle: String {
        if selectedModel.isAuto { return "자동" }
        let name = selectedModel.conciseDisplayName
        guard !selectedModel.supportedEfforts.isEmpty else { return name }
        return "\(name) · \(selectedEffort.displayName)"
    }

    private var modelOptions: some View {
        HStack(spacing: 6) {
            modelPicker
            if harness == .claude {
                proxyButton
            }
        }
    }

    private var sendButton: some View {
        Button(action: submit) {
            Group {
                if findStatus.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.up")
                }
            }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(trimmedPrompt.isEmpty ? Color.secondary : FineTheme.sendInk)
                .frame(width: FineTheme.compactControlHeight, height: FineTheme.compactControlHeight)
                .background(
                    RoundedRectangle(cornerRadius: FineTheme.compactControlRadius, style: .continuous)
                        .fill(trimmedPrompt.isEmpty ? FineTheme.controlFill : FineTheme.sendFill)
                )
        }
        .buttonStyle(.finePress)
        .disabled(trimmedPrompt.isEmpty || findStatus.isBusy)
        .accessibilityLabel(isFinding ? "찾기" : "대화 시작")
        .help(isFinding ? "찾기" : "대화 시작")
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        let initialPrompt = trimmedPrompt
        guard !initialPrompt.isEmpty else { return }
        if isFinding {
            // 못 찾으면 설명을 고쳐 다시 물을 수 있게 입력은 남겨 둔다.
            find(initialPrompt)
            return
        }
        prompt = ""
        let configuration = currentConfiguration
        guard configuration.isAutoModel else {
            appState.addSession(initialPrompt: initialPrompt, configuration: configuration)
            return
        }
        // "자동"은 실제 모델이 아니다. 라우터에게 물어 구체 설정으로 바꾼 뒤에 띄운다.
        // 워엄 상태에서 ~85ms이고, 실패하면 라우터가 폴백 설정을 돌려준다.
        let models = modelCatalog.models
        Task { @MainActor in
            let resolved = await QuickAutoRouter.resolve(
                prompt: initialPrompt, available: models, fallback: configuration
            )
            appState.addSession(initialPrompt: initialPrompt, configuration: resolved)
        }
    }

    private var selectedModel: QuickModelOption {
        modelCatalog.models.first(where: { $0.id == selectedModelID })
            ?? .defaultOption(for: harness)
    }

    private var harnessPicker: some View {
        HarnessSegmentedControl(selection: $harness)
            .help("대화를 실행할 하네스 선택")
    }

    private var modelPicker: some View {
        Button {
            isModelPickerPresented.toggle()
        } label: {
            FineControlPill(title: modelPickerTitle) {
                Image(systemName: selectedModel.isAuto ? "wand.and.stars" : "sparkle")
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .buttonStyle(.finePress)
        .fixedSize()
        .help(modelPickerHelp)
    }

    private var modelPickerHelp: String {
        switch harness {
        case .codex:
            return "Codex 모델 선택 · 라우터 없이 직접 실행"
        case .opencode:
            return "OpenCode 모델 선택 — opencode.json에 허용한 모델만 보입니다"
        case .omp:
            return "omp의 default 역할 모델을 고릅니다 — smol·slow·plan은 config.yml을 따릅니다"
        case .claude:
            return modelCatalog.routerAvailable
                ? "대화 모델 선택"
                : "라우터 오프라인 — Claude 모델만 사용 가능"
        }
    }

    private func constrainSelectedEffort() {
        let efforts = selectedModel.supportedEfforts
        guard !efforts.isEmpty, !efforts.contains(selectedEffort) else { return }
        selectedEffort = efforts.contains(.high) ? .high : (efforts.first ?? .high)
    }

    private var currentConfiguration: QuickSessionConfiguration {
        QuickSessionConfiguration(
            harness: harness,
            modelID: selectedModelID,
            effort: selectedEffort,
            proxyEnabled: proxyEnabled
        )
    }

    private func persistSelection() {
        QuickComposerPreferences.save(currentConfiguration)
    }

    private var proxyButton: some View {
        let requiresProxy = selectedModel.requiresProxy
        let locked = requiresProxy || selectedModel.isDefault || !modelCatalog.routerAvailable
        return Button {
            guard !locked else { return }
            proxyEnabled.toggle()
        } label: {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(proxyEnabled ? .primary : .secondary.opacity(0.72))
                .frame(width: FineTheme.compactControlHeight, height: FineTheme.compactControlHeight)
                .background(
                    RoundedRectangle(cornerRadius: FineTheme.compactControlRadius, style: .continuous)
                        .fill(Color.primary.opacity(proxyEnabled ? 0.10 : 0.045))
                )
        }
        .buttonStyle(.finePress)
        .disabled(locked)
        .help(proxyHelp)
    }

    private var proxyHelp: String {
        if selectedModel.isDefault { return "기본 모드는 라우터 없이 터미널의 ccv와 똑같이 실행됩니다" }
        if selectedModel.requiresProxy { return "Codex, Kimi, Gemini, Alibaba 모델은 프록시 세션이 필수입니다" }
        return "세션 내 모델 전환 허용"
    }

    private var sessionModeDescription: String {
        if modelCatalog.isLoading { return "모델 목록 확인 중" }
        switch harness {
        case .codex:
            return "Codex로 시작합니다"
        case .opencode:
            return selectedModel.isDefault
                ? "OpenCode 기본 모델로 시작합니다"
                : "OpenCode에서 선택한 모델로 시작합니다"
        case .omp:
            return selectedModel.isDefault
                ? "omp 설정의 역할 모델 그대로 시작합니다"
                : "default 역할만 바꿔 시작합니다 · smol·slow·plan은 그대로"
        case .claude:
            if selectedModel.isDefault { return "Claude 기본 모델로 시작합니다" }
            if selectedModel.isAuto { return "질문 난이도를 보고 모델과 깊이를 골라 시작합니다" }
            if !modelCatalog.routerAvailable { return "연결을 확인할 수 없어 Claude 모델만 사용할 수 있습니다" }
            if selectedModel.requiresProxy || proxyEnabled {
                return "대화 중에도 다른 제공사의 모델로 전환할 수 있습니다"
            }
            return "Claude로 시작합니다"
        }
    }
}
