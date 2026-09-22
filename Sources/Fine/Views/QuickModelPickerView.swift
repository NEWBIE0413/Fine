import SwiftUI

struct QuickModelPickerView: View {
    let models: [QuickModelOption]
    @Binding var selectedModelID: String
    @Binding var isPresented: Bool
    let dismissOnSelect: Bool
    let onRefresh: (() -> Void)?
    /// 모델과 깊이는 늘 같이 정해지는 값이다. 컴포저 줄에 따로 두면 자리만 차지하고
    /// 둘의 관계가 보이지 않으므로 같은 패널에서 고르게 한다.
    var selectedEffort: Binding<QuickEffort>?
    var isLoading: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tier: QuickModelTier
    @State private var provider: QuickModelProvider
    @State private var query = ""
    @Namespace private var selection

    init(models: [QuickModelOption], selectedModelID: Binding<String>, isPresented: Binding<Bool>,
         dismissOnSelect: Bool = true, onRefresh: (() -> Void)? = nil,
         selectedEffort: Binding<QuickEffort>? = nil, isLoading: Bool = false) {
        self.models = models
        _selectedModelID = selectedModelID
        _isPresented = isPresented
        self.dismissOnSelect = dismissOnSelect
        self.onRefresh = onRefresh
        self.selectedEffort = selectedEffort
        self.isLoading = isLoading
        let selected = models.first { $0.id == selectedModelID.wrappedValue }
        let initial = selected?.provider ?? models.first?.provider ?? .claude
        _tier = State(initialValue: initial.tier)
        _provider = State(initialValue: initial)
    }

    private var availableTiers: [QuickModelTier] {
        QuickModelTier.allCases.filter { candidate in models.contains { $0.provider.tier == candidate } }
    }
    private var providers: [QuickModelProvider] {
        QuickModelProvider.allCases.filter { candidate in
            candidate.tier == tier && models.contains { $0.provider == candidate }
        }
    }
    private var visibleModels: [QuickModelOption] {
        models.filter {
            $0.provider == provider && (query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query))
        }
    }
    private var panelHeight: CGFloat {
        let count = models.filter { $0.provider == provider }.count
        let rows = max(2, min(7, count))
        let effortRow: CGFloat = selectedEffort != nil ? 45 : 0
        // 상한은 그대로 둔다. 깊이 행이 붙으면 목록이 한 줄 덜 보일 뿐,
        // 패널이 최소 창을 넘지 않는 것이 먼저다.
        return min(410, CGFloat(rows) * 44 + 76 + (availableTiers.count > 1 ? 44 : 0)
                   + (models.count > 8 ? 40 : 0) + effortRow)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if availableTiers.count > 1 {
                HStack(spacing: 4) {
                    ForEach(availableTiers) { candidate in
                        Button { tier = candidate } label: {
                            Text(candidate.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(tier == candidate ? .primary : .secondary)
                                .padding(.horizontal, 14)
                                .frame(height: 26)
                                .background {
                                    if tier == candidate {
                                        Capsule().fill(FineTheme.controlFill)
                                            .matchedGeometryEffect(id: "tier", in: selection)
                                    }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(tier == candidate ? .isSelected : [])
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 1), value: tier)
            }
            if models.count > 8 {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.tertiary)
                    TextField("모델 찾기", text: $query)
                        .textFieldStyle(.plain).font(.system(size: 12))
                        .accessibilityLabel("모델 검색")
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }.buttonStyle(.plain).help("검색 지우기")
                    }
                }
                .padding(.horizontal, 10).frame(height: 30)
                .background(FineTheme.pickerRailFill, in: RoundedRectangle(cornerRadius: 7))
                .padding(.horizontal, 16).padding(.bottom, 10)
            }
            Rectangle().fill(FineTheme.divider).frame(height: 1)
            HStack(spacing: 0) {
                if providers.count > 1 {
                    providerRail.frame(width: 126)
                    Rectangle().fill(FineTheme.divider).frame(width: 1)
                }
                modelList.frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            effortSection
        }
        .frame(maxWidth: 500)
        .frame(height: panelHeight)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 1), value: panelHeight)
        .background(FineTheme.workspace)
        .onChange(of: tier) { _, _ in
            if !providers.contains(provider), let first = providers.first { provider = first }
            query = ""
        }
        .onChange(of: selectedModelID) { _, id in
            guard let selected = models.first(where: { $0.id == id }) else { return }
            tier = selected.provider.tier
            provider = selected.provider
        }
        .onChange(of: models) { _, updated in
            guard !updated.contains(where: { $0.provider == provider }), let first = updated.first else { return }
            tier = first.provider.tier
            provider = first.provider
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("모델 선택").font(.system(size: 14, weight: .semibold))
                Text(isLoading ? "목록을 확인하고 있습니다" : "\(provider.title) · \(models.filter { $0.provider == provider }.count)개의 모델")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let onRefresh {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium))
                        .frame(width: 26, height: 26).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                    .disabled(isLoading).help("모델 목록 새로고침")
            }
            if dismissOnSelect {
                Button { isPresented = false } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        .frame(width: 26, height: 26).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(.secondary).help("모델 선택 닫기")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private var providerRail: some View {
        ScrollView {
            VStack(spacing: 3) {
                ForEach(providers) { candidate in
                    Button { provider = candidate; query = "" } label: {
                        Text(candidate.title)
                            .font(.system(size: 11, weight: provider == candidate ? .semibold : .medium))
                            .foregroundStyle(provider == candidate ? .primary : .secondary)
                            .lineLimit(2).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                            .padding(.horizontal, 10)
                            .background {
                                if provider == candidate {
                                    RoundedRectangle(cornerRadius: 7).fill(.white)
                                        .matchedGeometryEffect(id: "provider", in: selection)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help(candidate.title)
                    .accessibilityLabel("\(candidate.title) provider")
                    .accessibilityAddTraits(provider == candidate ? .isSelected : [])
                }
            }.padding(8)
        }
        .background(FineTheme.pickerRailFill)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 1), value: provider)
    }

    private var modelList: some View {
        Group {
            if visibleModels.isEmpty {
                VStack(spacing: 7) {
                    Text(isLoading ? "모델을 불러오는 중…" : "표시할 모델이 없습니다")
                        .font(.system(size: 12, weight: .medium))
                    if !query.isEmpty { Text("다른 이름으로 검색해 보세요").font(.system(size: 11)).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(visibleModels) { model in
                            ModelChoiceRow(model: model, selected: selectedModelID == model.id) { select(model) }
                        }
                    }.padding(8)
                }
                .id(provider)
            }
        }
    }

    private func select(_ model: QuickModelOption) {
        // 닫을지 말지는 "방금 고른 모델"로 판단해야 한다. selectedModelID에 쓴 값은
        // 아직 반영되기 전이라, 직전 모델(예: 깊이가 없는 "기본")을 기준으로 삼으면
        // 깊이가 있는 모델을 골라도 패널이 곧바로 닫혀 깊이를 고를 기회가 사라진다.
        let offersEffort = selectedEffort != nil && !model.isAuto && !model.supportedEfforts.isEmpty
        selectedModelID = model.id
        guard dismissOnSelect, !offersEffort else { return }
        DispatchQueue.main.async { isPresented = false }
    }

    private var currentModel: QuickModelOption? { models.first { $0.id == selectedModelID } }

    private var effortChoices: [QuickEffort] {
        guard selectedEffort != nil, let model = currentModel, !model.isAuto else { return [] }
        return model.supportedEfforts
    }

    @ViewBuilder
    private var effortSection: some View {
        if let binding = selectedEffort, let model = currentModel {
            Rectangle().fill(FineTheme.divider).frame(height: 1)
            HStack(spacing: 6) {
                Text("생각 깊이")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if effortChoices.isEmpty {
                    Text(model.isAuto ? "질문에 맞춰 자동으로" : "하네스 기본값")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(effortChoices) { effort in
                        Button { binding.wrappedValue = effort } label: {
                            Text(effort.displayName)
                                .font(.system(size: 11, weight: binding.wrappedValue == effort ? .semibold : .medium))
                                .foregroundStyle(binding.wrappedValue == effort ? .primary : .secondary)
                                .padding(.horizontal, 11)
                                .frame(height: 26)
                                .background {
                                    if binding.wrappedValue == effort {
                                        Capsule().fill(FineTheme.controlFill)
                                            .matchedGeometryEffect(id: "effort", in: selection)
                                    }
                                }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(binding.wrappedValue == effort ? .isSelected : [])
                    }
                    Button("완료") { isPresented = false }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.leading, 6)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 1),
                       value: binding.wrappedValue)
        }
    }
}

private struct ModelChoiceRow: View {
    let model: QuickModelOption
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.conciseDisplayName)
                        .font(.system(size: 12, weight: selected ? .semibold : .medium))
                        .foregroundStyle(.primary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.isDefault {
                        Text("터미널의 기본 설정 사용").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary.opacity(selected ? 0.7 : 0))
                    .frame(width: 12)
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .background((selected ? FineTheme.controlFill : hovering ? FineTheme.hoverFill : .clear),
                        in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(model.id.isEmpty ? model.displayName : model.id)
        .accessibilityLabel(model.conciseDisplayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
