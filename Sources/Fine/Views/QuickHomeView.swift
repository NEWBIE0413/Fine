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

    init() {
        let saved = QuickComposerPreferences.load()
        _harness = State(initialValue: saved.harness)
        _selectedModelID = State(initialValue: saved.modelID)
        _selectedEffort = State(initialValue: saved.effort)
        _proxyEnabled = State(initialValue: saved.proxyEnabled)
    }

    var body: some View {
        QuickHomePresentation {
            VStack(spacing: 14) {
                QuickHomeComposer(prompt: $prompt, onSubmit: submit) {
                    composerControls
                }
                Text(sessionModeDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
        }
        .fineOverlay(isPresented: $isModelPickerPresented) {
            QuickModelPickerView(
                models: modelCatalog.models,
                selectedModelID: $selectedModelID,
                isPresented: $isModelPickerPresented,
                onRefresh: { modelCatalog.refresh(harness: harness) },
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
            harnessPicker
        } options: {
            modelOptions
        } send: {
            sendButton
        }
    }

    private var modelOptions: some View {
        HStack(spacing: 6) {
            modelPicker
            if !selectedModel.supportedEfforts.isEmpty {
                effortPicker
            }
            if harness == .claude {
                proxyButton
            }
        }
    }

    private var sendButton: some View {
        Button(action: submit) {
            Image(systemName: "arrow.up")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(trimmedPrompt.isEmpty ? Color.secondary : .white)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(trimmedPrompt.isEmpty
                            ? Color.black.opacity(0.05)
                            : Color(red: 0.22, green: 0.27, blue: 0.23))
                )
        }
        .buttonStyle(.plain)
        .disabled(trimmedPrompt.isEmpty)
        .accessibilityLabel("대화 시작")
        .help("대화 시작")
    }

    private var trimmedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        let initialPrompt = trimmedPrompt
        guard !initialPrompt.isEmpty else { return }
        prompt = ""
        appState.addSession(
            initialPrompt: initialPrompt,
            configuration: currentConfiguration
        )
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
            pickerLabel(selectedModel.conciseDisplayName, icon: "sparkle")
        }
        .buttonStyle(.plain)
        .help(modelPickerHelp)
    }

    private var modelPickerHelp: String {
        switch harness {
        case .codex:
            return "Codex 모델 선택 · 라우터 없이 직접 실행"
        case .opencode:
            return "OpenCode 모델 선택 — opencode.json에 허용한 모델만 보입니다"
        case .claude:
            return modelCatalog.routerAvailable
                ? "대화 모델 선택"
                : "라우터 오프라인 — Claude 모델만 사용 가능"
        }
    }

    private var effortPicker: some View {
        Menu {
            ForEach(selectedModel.supportedEfforts) { effort in
                Button {
                    selectedEffort = effort
                } label: {
                    if selectedEffort == effort {
                        Label(effort.displayName, systemImage: "checkmark")
                    } else {
                        Text(effort.displayName)
                    }
                }
            }
        } label: {
            pickerLabel(selectedEffort.displayName, icon: "dial.medium")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("응답 생성 effort")
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
        .buttonStyle(.plain)
        .disabled(locked)
        .help(proxyHelp)
    }

    private var proxyHelp: String {
        if selectedModel.isDefault { return "기본 모드는 라우터 없이 터미널의 ccv와 똑같이 실행됩니다" }
        if selectedModel.requiresProxy { return "Codex, Kimi, Gemini, Alibaba 모델은 프록시 세션이 필수입니다" }
        return "세션 내 모델 전환 허용"
    }

    private func pickerLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                .frame(maxWidth: 210, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.secondary.opacity(0.65))
        }
        .foregroundColor(.primary.opacity(0.75))
        .padding(.horizontal, 9)
        .frame(height: FineTheme.compactControlHeight)
        .background(
            RoundedRectangle(cornerRadius: FineTheme.compactControlRadius, style: .continuous)
                .fill(FineTheme.controlFill)
        )
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
        case .claude:
            if selectedModel.isDefault { return "Claude 기본 모델로 시작합니다" }
            if !modelCatalog.routerAvailable { return "연결을 확인할 수 없어 Claude 모델만 사용할 수 있습니다" }
            if selectedModel.requiresProxy || proxyEnabled {
                return "대화 중에도 다른 제공사의 모델로 전환할 수 있습니다"
            }
            return "Claude로 시작합니다"
        }
    }
}
