import SwiftUI

/// 하네스가 넷이 되면 세그먼트는 컴포저 줄의 절반을 먹는다.
/// 거의 바꾸지 않는 값이므로 드롭다운 하나로 접고, 현재 것만 마크와 이름으로 보인다.
struct HarnessSegmentedControl: View {
    @Binding var selection: QuickHarness
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Menu {
            ForEach(QuickHarness.allCases) { harness in
                Button { selection = harness } label: {
                    if selection == harness {
                        Label(harness.title, systemImage: "checkmark")
                    } else {
                        Text(harness.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(selection.rawValue, bundle: .module)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundStyle(.primary.opacity(0.75))
                Text(selection.title)
                    .font(.system(size: 12, weight: .medium))
                    .fineTracking(12)
                    .fixedSize()
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.65))
            }
            .foregroundStyle(.primary.opacity(0.75))
            .padding(.horizontal, 9)
            .frame(height: FineTheme.compactControlHeight)
            .background(
                FinePalette.resolve(colorScheme).controlFill,
                in: RoundedRectangle(cornerRadius: FineTheme.compactControlRadius, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        // Menu 자체는 라벨보다 낮게 보고한다. 컴포저 줄의 다른 컨트롤과 높이를 맞춘다.
        .frame(height: FineTheme.compactControlHeight)
        .accessibilityLabel("하네스")
        .accessibilityValue(selection.title)
    }
}
