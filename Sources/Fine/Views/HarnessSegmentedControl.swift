import SwiftUI

/// 하네스는 거의 바꾸지 않는 값이라, 세 칸을 모두 글자로 채울 이유가 없다.
/// 고른 것만 이름을 보이고 나머지는 마크만 둔다 — 한 번의 클릭으로 바꾸는 성질과
/// 현재 상태가 보이는 성질은 그대로 두면서 폭만 줄인다.
struct HarnessSegmentedControl: View {
    @Binding var selection: QuickHarness
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(QuickHarness.allCases) { harness in
                let isSelected = selection == harness
                Button { selection = harness } label: {
                    HStack(spacing: 5) {
                        Image(harness.rawValue, bundle: .module)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                            .foregroundStyle(isSelected ? .primary : .secondary)
                        if isSelected {
                            Text(harness.title)
                                .font(.system(size: 12, weight: .semibold))
                                .fineTracking(12)
                                .fixedSize()
                                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .leading)))
                        }
                    }
                    .padding(.horizontal, isSelected ? 9 : 7)
                    .frame(height: FineTheme.compactControlHeight - 4)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                // 어두운 쪽에서 새하얀 칩은 혼자 튄다. 옅게 띄우기만 한다.
                                .fill(.white.opacity(colorScheme == .dark ? 0.16 : 0.94))
                                .matchedGeometryEffect(id: "harness", in: highlight)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.finePress)
                .help(harness.title)
                .accessibilityLabel(harness.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            FinePalette.resolve(colorScheme).controlFill,
            in: RoundedRectangle(cornerRadius: FineTheme.compactControlRadius)
        )
        .fixedSize()
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 1), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("하네스")
    }
}
