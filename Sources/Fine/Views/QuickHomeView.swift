import SwiftUI

struct QuickHomeView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var modelCatalog = QuickModelCatalog()
    @State private var prompt = ""
    @State private var selectedModelID: String
    @State private var selectedEffort: QuickEffort
    @State private var proxyEnabled: Bool
    @FocusState private var isPromptFocused: Bool

    init() {
        let saved = QuickComposerPreferences.load()
        _selectedModelID = State(initialValue: saved.modelID)
        _selectedEffort = State(initialValue: saved.effort)
        _proxyEnabled = State(initialValue: saved.proxyEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text("무엇을 도와드릴까요?")
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.45)
                    .foregroundStyle(.primary)
                Text("모델과 effort를 선택하고 바로 대화를 시작하세요.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if prompt.isEmpty {
                        Text("메시지를 입력하세요")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary.opacity(0.62))
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $prompt, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .lineLimit(3...10)
                        .focused($isPromptFocused)
                        .onSubmit(submit)
                }
                .frame(minHeight: 72, alignment: .topLeading)
                .padding(16)

                Divider()

                HStack(spacing: 8) {
                    modelPicker
                    effortPicker
                    proxyButton
                    Text(sessionModeDescription)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Button(action: submit) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(trimmedPrompt.isEmpty ? Color.secondary.opacity(0.55) : .white)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(
                                    cornerRadius: FineTheme.compactControlRadius,
                                    style: .continuous
                                )
                                .fill(trimmedPrompt.isEmpty ? FineTheme.controlFill : Color.primary)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmedPrompt.isEmpty)
                }
                .padding(10)
            }
            .background(
                RoundedRectangle(cornerRadius: FineTheme.composerCornerRadius, style: .continuous)
                    .fill(FineTheme.workspace)
            )
            .overlay(
                RoundedRectangle(cornerRadius: FineTheme.composerCornerRadius, style: .continuous)
                    .stroke(FineTheme.divider, lineWidth: 1)
            )
        }
        .frame(maxWidth: FineTheme.homeContentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 56)
        .padding(.vertical, 48)
        .onAppear {
            isPromptFocused = true
            modelCatalog.refresh()
        }
        .onChange(of: selectedModelID) { _, modelID in
            if modelID.hasPrefix("claude-codex-")
                || modelID.hasPrefix("claude-kimi-")
                || modelID.hasPrefix("claude-gemini-") {
                proxyEnabled = true
            }
            constrainSelectedEffort()
            persistSelection()
        }
        .onChange(of: selectedEffort) { persistSelection() }
        .onChange(of: proxyEnabled) { persistSelection() }
        .onChange(of: modelCatalog.models) { _, models in
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
            ?? QuickModelCatalog.fallbackModels[1]
    }

    private var modelPicker: some View {
        Menu {
            Section("Claude") {
                ForEach(modelCatalog.models.filter { !$0.isCodex && !$0.isKimi && !$0.isGemini }) { model in
                    modelButton(model)
                }
            }
            let codexModels = modelCatalog.models.filter(\.isCodex)
            if !codexModels.isEmpty {
                Section("Codex · 프록시") {
                    ForEach(codexModels) { model in modelButton(model) }
                }
            }
            let kimiModels = modelCatalog.models.filter(\.isKimi)
            if !kimiModels.isEmpty {
                Section("Kimi · 프록시") {
                    ForEach(kimiModels) { model in modelButton(model) }
                }
            }
            let geminiModels = modelCatalog.models.filter(\.isGemini)
            if !geminiModels.isEmpty {
                Section("Gemini · 프록시") {
                    ForEach(geminiModels) { model in modelButton(model) }
                }
            }
        } label: {
            pickerLabel(selectedModel.displayName, icon: "sparkle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(modelCatalog.routerAvailable ? "대화 모델 선택" : "라우터 오프라인 — Claude 모델만 사용 가능")
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

    private func modelButton(_ model: QuickModelOption) -> some View {
        Button {
            selectedModelID = model.id
        } label: {
            if selectedModelID == model.id {
                Label(model.displayName, systemImage: "checkmark")
            } else {
                Text(model.displayName)
            }
        }
    }

    private func constrainSelectedEffort() {
        let efforts = selectedModel.supportedEfforts
        guard !efforts.contains(selectedEffort) else { return }
        selectedEffort = efforts.contains(.high) ? .high : (efforts.first ?? .high)
    }

    private var currentConfiguration: QuickSessionConfiguration {
        QuickSessionConfiguration(
            modelID: selectedModelID,
            effort: selectedEffort,
            proxyEnabled: proxyEnabled
        )
    }

    private func persistSelection() {
        QuickComposerPreferences.save(currentConfiguration)
    }

    private var proxyButton: some View {
        let requiresProxy = selectedModel.isCodex || selectedModel.isKimi || selectedModel.isGemini
        return Button {
            guard modelCatalog.routerAvailable, !requiresProxy else { return }
            proxyEnabled.toggle()
        } label: {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(proxyEnabled ? .primary : .secondary.opacity(0.72))
                .frame(width: 27, height: 25)
                .background(
                    RoundedRectangle(cornerRadius: FineTheme.compactControlRadius, style: .continuous)
                        .fill(Color.primary.opacity(proxyEnabled ? 0.10 : 0.045))
                )
        }
        .buttonStyle(.plain)
        .disabled(!modelCatalog.routerAvailable || requiresProxy)
        .help(requiresProxy ? "Codex, Kimi, Gemini 모델은 프록시 세션이 필수입니다" : "세션 내 모델 전환 허용")
    }

    private func pickerLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.secondary.opacity(0.65))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 8)
        .frame(height: 25)
        .background(
            RoundedRectangle(cornerRadius: FineTheme.compactControlRadius, style: .continuous)
                .fill(FineTheme.controlFill)
        )
    }

    private var sessionModeDescription: String {
        if modelCatalog.isLoading { return "모델 목록 확인 중" }
        if !modelCatalog.routerAvailable { return "라우터 오프라인 · Claude 직결만 사용 가능" }
        if selectedModel.isCodex || selectedModel.isKimi || selectedModel.isGemini || proxyEnabled {
            return "프록시 세션 · /model에서 Claude·Codex·Kimi·Gemini 전환 가능"
        }
        return "Claude 직결 · 세션 안에서 Codex 전환 불가"
    }
}
