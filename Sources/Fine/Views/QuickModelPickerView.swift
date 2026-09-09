import SwiftUI

struct QuickModelPickerView: View {
    let models: [QuickModelOption]
    @Binding var selectedModelID: String
    @Binding var isPresented: Bool
    let dismissOnSelect: Bool
    let onRefresh: (() -> Void)?

    @State private var tier: QuickModelTier
    @State private var provider: QuickModelProvider

    init(
        models: [QuickModelOption],
        selectedModelID: Binding<String>,
        isPresented: Binding<Bool>,
        dismissOnSelect: Bool = true,
        onRefresh: (() -> Void)? = nil
    ) {
        self.models = models
        _selectedModelID = selectedModelID
        _isPresented = isPresented
        self.dismissOnSelect = dismissOnSelect
        self.onRefresh = onRefresh
        let selected = models.first { $0.id == selectedModelID.wrappedValue }
        let initialProvider = selected?.provider ?? models.first?.provider ?? .claude
        _tier = State(initialValue: initialProvider.tier)
        _provider = State(initialValue: initialProvider)
    }

    private var availableTiers: [QuickModelTier] {
        QuickModelTier.allCases.filter { candidate in
            models.contains { $0.provider.tier == candidate }
        }
    }

    private var providers: [QuickModelProvider] {
        QuickModelProvider.allCases.filter { candidate in
            candidate.tier == tier && models.contains { $0.provider == candidate }
        }
    }

    private var visibleModels: [QuickModelOption] {
        models.filter { $0.provider == provider }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let onRefresh {
                HStack {
                    Text("모델")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button(action: onRefresh) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help("모델 목록 즉시 새로고침")
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                Divider()
            }
            if availableTiers.count > 1 {
                Picker("모델 유형", selection: $tier) {
                    ForEach(availableTiers) { tier in
                        Text(tier.title).tag(tier)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(12)

                Divider()
            }

            HStack(spacing: 0) {
                providerRail
                    .frame(width: 128)

                Divider()

                modelList
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: 500)
        .frame(height: 320)
        .background(FineTheme.workspace)
        .onChange(of: tier) { _, newTier in
            guard provider.tier != newTier else { return }
            provider = providers.first ?? (newTier == .free ? .alibabaFree : .claude)
        }
        .onChange(of: selectedModelID) { _, modelID in
            guard let selected = models.first(where: { $0.id == modelID }) else { return }
            tier = selected.provider.tier
            provider = selected.provider
        }
        .onChange(of: models) { _, models in
            guard !models.contains(where: { $0.provider == provider }),
                  let first = models.first else { return }
            tier = first.provider.tier
            provider = first.provider
        }
    }

    private var providerRail: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(providers) { candidate in
                Button {
                    provider = candidate
                } label: {
                    HStack(spacing: 8) {
                        Text(candidate.title)
                            .font(.system(size: 12, weight: provider == candidate ? .semibold : .medium))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: FineTheme.compactControlRadius)
                            .fill(provider == candidate ? FineTheme.controlFill : .clear)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(candidate.title) provider")
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(FineTheme.pickerRailFill)
    }

    private var modelList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(visibleModels) { model in
                    Button {
                        select(model)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selectedModelID == model.id ? "checkmark" : "circle")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(selectedModelID == model.id ? .primary : .tertiary)
                                .frame(width: 12)
                            Text(model.conciseDisplayName)
                                .font(.system(size: 12, weight: selectedModelID == model.id ? .semibold : .regular))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(
                            RoundedRectangle(cornerRadius: FineTheme.compactControlRadius)
                                .fill(selectedModelID == model.id ? FineTheme.controlFill : .clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(model.conciseDisplayName)
                }
            }
            .padding(8)
        }
    }

    /// Commit the selection first and dismiss on the next turn so the overlay
    /// never tears down while its own state change is still propagating.
    private func select(_ model: QuickModelOption) {
        selectedModelID = model.id
        guard dismissOnSelect else { return }
        DispatchQueue.main.async { isPresented = false }
    }
}
