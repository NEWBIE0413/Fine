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
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(Color(red: 0.92, green: 0.45, blue: 0.35))
                    Text("새 대화 시작")
                        .font(.system(size: 30, weight: .semibold))
                        .tracking(-0.5)
                }
                Text("무엇을 도와드릴까요?")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary.opacity(0.85))
            }

            VStack(alignment: .leading, spacing: 14) {
                ZStack(alignment: .topLeading) {
                    if prompt.isEmpty {
                        Text("메시지를 입력하세요...")
                            .font(.system(size: 16))
                            .foregroundColor(Color.secondary.opacity(0.55))
                            .padding(.top, 2)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $prompt, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                        .lineLimit(3...10)
                        .focused($isPromptFocused)
                        .onSubmit(submit)
                        .padding(.horizontal, 4)
                }
                .frame(minHeight: 56, alignment: .topLeading)

                HStack(spacing: 10) {
                    modelPicker
                    effortPicker
                    proxyButton
                    Spacer()
                    Button(action: submit) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(trimmedPrompt.isEmpty ? .secondary.opacity(0.55) : .white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(trimmedPrompt.isEmpty ? Color.primary.opacity(0.12) : .black))
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmedPrompt.isEmpty)
                }

                Text(sessionModeDescription)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.72))
                    .lineLimit(1)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
                    .shadow(color: .black.opacity(0.08), radius: 24, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.black.opacity(0.10), lineWidth: 1)
            )
        }
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .onAppear {
            isPromptFocused = true
            modelCatalog.refresh()
        }
        .onChange(of: selectedModelID) { _, modelID in
            if modelID.hasPrefix("claude-codex-") { proxyEnabled = true }
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
                ForEach(modelCatalog.models.filter { !$0.isCodex }) { model in
                    modelButton(model)
                }
            }
            let codexModels = modelCatalog.models.filter(\.isCodex)
            if !codexModels.isEmpty {
                Section("Codex · 프록시") {
                    ForEach(codexModels) { model in modelButton(model) }
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
        let isCodex = selectedModel.isCodex
        return Button {
            guard modelCatalog.routerAvailable, !isCodex else { return }
            proxyEnabled.toggle()
        } label: {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(proxyEnabled ? .primary : .secondary.opacity(0.72))
                .frame(width: 27, height: 25)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(proxyEnabled ? 0.10 : 0.045))
                )
        }
        .buttonStyle(.plain)
        .disabled(!modelCatalog.routerAvailable || isCodex)
        .help(isCodex ? "Codex 모델은 프록시 세션이 필수입니다" : "세션 내 Claude↔Codex 전환 허용")
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
        .padding(.horizontal, 9)
        .frame(height: 25)
        .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.045)))
    }

    private var sessionModeDescription: String {
        if modelCatalog.isLoading { return "모델 목록 확인 중" }
        if !modelCatalog.routerAvailable { return "라우터 오프라인 · Claude 직결만 사용 가능" }
        if selectedModel.isCodex || proxyEnabled {
            return "프록시 세션 · /model에서 Claude↔Codex 전환 가능"
        }
        return "Claude 직결 · 세션 안에서 Codex 전환 불가"
    }
}
