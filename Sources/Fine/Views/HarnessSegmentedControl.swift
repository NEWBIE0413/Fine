import SwiftUI

struct HarnessSegmentedControl: View {
    @Binding var selection: QuickHarness
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(QuickHarness.allCases) { harness in
                Button { selection = harness } label: {
                    Text(harness.title)
                        .font(.system(size: 12, weight: selection == harness ? .semibold : .medium))
                        .foregroundStyle(selection == harness ? .primary : .secondary)
                        .padding(.horizontal, 10)
                        .frame(height: FineTheme.compactControlHeight - 4)
                        .background {
                            if selection == harness {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(.white.opacity(0.94))
                                    .matchedGeometryEffect(id: "harness", in: highlight)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == harness ? .isSelected : [])
            }
        }
        .padding(2)
        .background(FineTheme.controlFill, in: RoundedRectangle(cornerRadius: FineTheme.compactControlRadius))
        .fixedSize()
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 1), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("하네스")
    }
}
