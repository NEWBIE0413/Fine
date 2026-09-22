import SwiftUI

/// 앱이 따를 외형. 시스템을 따르거나, 명시적으로 고정한다.
enum FineAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "시스템"
        case .light: "밝게"
        case .dark: "어둡게"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon.stars"
        }
    }

    /// nil이면 시스템 설정을 그대로 따른다.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// 사이드바 바닥에 앉는 작은 전환기. 아이콘만 두고 현재 값만 띄운다 —
/// 자주 만지는 설정이 아니므로 글자로 세 칸을 채울 이유가 없다.
struct AppearancePicker: View {
    @AppStorage("fineAppearance") private var stored = FineAppearance.system.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var highlight

    private var selection: FineAppearance {
        FineAppearance(rawValue: stored) ?? .system
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(FineAppearance.allCases) { appearance in
                let isSelected = selection == appearance
                Button { stored = appearance.rawValue } label: {
                    Image(systemName: appearance.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .frame(width: 30, height: 22)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(.white.opacity(colorScheme == .dark ? 0.16 : 0.94))
                                    .matchedGeometryEffect(id: "appearance", in: highlight)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.finePress)
                .help(appearance.title)
                .accessibilityLabel(appearance.title)
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
        .accessibilityLabel("외형")
    }
}
