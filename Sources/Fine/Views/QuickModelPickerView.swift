import SwiftUI

struct QuickModelPickerView: View {
    let models: [QuickModelOption]
    @Binding var selectedModelID: String
    @Binding var isPresented: Bool
    let dismissOnSelect: Bool
    let onRefresh: (() -> Void)?
    var isLoading: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tier: QuickModelTier
    @State private var provider: QuickModelProvider
    @State private var query = ""
    @Namespace private var selection

    init(models: [QuickModelOption], selectedModelID: Binding<String>, isPresented: Binding<Bool>,
         dismissOnSelect: Bool = true, onRefresh: (() -> Void)? = nil, isLoading: Bool = false) {
        self.models = models
        _selectedModelID = selectedModelID
        _isPresented = isPresented
        self.dismissOnSelect = dismissOnSelect
        self.onRefresh = onRefresh
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
        return min(410, CGFloat(rows) * 44 + 76 + (availableTiers.count > 1 ? 44 : 0) + (models.count > 8 ? 40 : 0))
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
        selectedModelID = model.id
        guard dismissOnSelect else { return }
        DispatchQueue.main.async { isPresented = false }
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
