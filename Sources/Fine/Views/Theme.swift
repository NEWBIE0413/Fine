import SwiftUI

enum FineTheme {
    static let sidebarWidth: CGFloat = 248
    static let sidebarInset: CGFloat = 12
    static let titlebarClearance: CGFloat = 40
    static let rowCornerRadius: CGFloat = 8
    static let rowVerticalPadding: CGFloat = 8
    static let rowHorizontalPadding: CGFloat = 10
    static let iconSize: CGFloat = 12
    static let iconFrame: CGFloat = 16
    static let compactControlHeight: CGFloat = 30
    static let compactControlRadius: CGFloat = 7
    static let composerCornerRadius: CGFloat = 14
    static let homeContentWidth: CGFloat = 680

    // 여기 색들은 뷰마다 colorScheme을 읽지 않고 상수로 쓰인다. 그래서 값 자체가
    // 창의 외형을 따라 풀려야 한다 — 검정 5%는 어두운 바탕에서 보이지 않고,
    // 흰 면은 어두운 패널 위에서 혼자 불을 켠 것처럼 튄다.
    static let workspace = Color(nsColor: .textBackgroundColor)
    static let divider = Color.adaptive(light: FinePalette.light.divider, dark: FinePalette.dark.divider)
    static let hoverFill = Color.adaptive(light: .black.opacity(0.04), dark: .white.opacity(0.05))
    static let selectedFill = Color.adaptive(light: FinePalette.light.selectedFill, dark: FinePalette.dark.selectedFill)
    static let selectedRim = Color.adaptive(light: FinePalette.light.selectedRim, dark: FinePalette.dark.selectedRim)
    static let controlFill = Color.adaptive(light: FinePalette.light.controlFill, dark: FinePalette.dark.controlFill)
    static let pickerRailFill = Color.adaptive(light: .black.opacity(0.018), dark: .white.opacity(0.025))
    /// 피커 레일에서 고른 칸. 밝은 쪽은 흰 면이 레일 위로 떠오르고, 어두운 쪽은 한 단만 밝힌다.
    static let pickerSelection = Color.adaptive(light: .white, dark: .white.opacity(0.11))
    static let overlayScrim = Color.adaptive(light: .black.opacity(0.06), dark: .black.opacity(0.32))
    static let overlayShadow = Color.adaptive(light: .black.opacity(0.14), dark: .black.opacity(0.5))
    static let overlayCornerRadius: CGFloat = 12
    static let glassSheenTop = Color.white.opacity(0.30)
    static let glassSheenMiddle = Color.white.opacity(0.10)
    static let glassTintBottom = Color(nsColor: .windowBackgroundColor).opacity(0.08)
    static let glassEdge = Color.adaptive(light: .black.opacity(0.08), dark: .white.opacity(0.10))
    /// 보내기 버튼. 어두운 쪽에서 짙은 녹색은 바탕에 묻히므로 밝은 면에 어두운 화살표로 뒤집는다.
    static let sendFill = Color.adaptive(light: Color(red: 0.22, green: 0.27, blue: 0.23), dark: FinePalette.dark.ink)
    static let sendInk = Color.adaptive(light: .white, dark: FinePalette.dark.base)
    /// 찾기 모드의 색. 대화를 시작하는 초록과 겹치지 않게 푸른 쪽으로 둔다.
    static let findAccent = Color.adaptive(
        light: Color(red: 0.24, green: 0.45, blue: 0.66),
        dark: Color(red: 0.47, green: 0.64, blue: 1.0)
    )
}

extension Color {
    /// 창의 실제 외형에 따라 풀리는 색. SwiftUI는 이 NSColor를 그리는 자리의
    /// 외형으로 풀어내므로, 정적 상수로 두어도 테마를 따라간다.
    static func adaptive(light: Color, dark: Color) -> Color {
        let light = NSColor(light), dark = NSColor(dark)
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

/// 인사말처럼 큰 글자의 서체. 밝은 쪽에는 세리프가 어울리지만 어두운 쪽에서는
/// 가는 세리프 획이 배경에 먹혀 지저분해진다. 그쪽은 산세리프로 간다.
///
/// Pretendard가 깔려 있으면 그것을 쓰고, 없으면 시스템 서체로 떨어진다 —
/// `Font.custom`은 이름을 못 찾으면 조용히 시스템으로 돌아간다.
enum FineDisplayFont {
    static func greeting(size: CGFloat, isDark: Bool) -> Font {
        guard isDark else {
            return .system(size: size, weight: .regular, design: .serif)
        }
        return .custom("Pretendard-Medium", size: size)
    }

    /// 세리프는 같은 크기에서 더 크게 읽히고 자간도 더 조여야 한다.
    static func greetingTracking(isDark: Bool) -> CGFloat { isDark ? -0.9 : -0.5 }
}

/// 누르는 순간 반응한다. 놓을 때까지 기다리면 직접 만지는 느낌이 사라진다.
/// 스프링은 critically damped — 버튼은 튕길 이유가 없다.
struct FinePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? scale : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 1),
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == FinePressStyle {
    static var finePress: FinePressStyle { FinePressStyle() }
}

/// 글자 크기에 따라 자간이 달라져야 한다. 큰 글자는 그대로 두면 성기게 읽히고,
/// 작은 글자는 조금 벌려야 읽힌다. 한 값을 모든 크기에 쓰면 어딘가는 틀린다.
extension View {
    func fineTracking(_ size: CGFloat) -> some View {
        tracking(size >= 20 ? -0.4 : size >= 15 ? -0.2 : size <= 11 ? 0.15 : 0)
    }
}

struct GlassSidebarBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // 어두운 쪽에서는 흰 광택이 뿌옇게 뜬다. 같은 구조에 세기만 낮춘다.
        let sheen = colorScheme == .dark ? 0.10 : 1.0
        ZStack(alignment: .trailing) {
            Rectangle()
                .fill(.ultraThinMaterial)

            // 밝은 쪽에서는 유리가 종이보다 밝지만, 어두운 쪽에서는 반대여야 한다.
            Rectangle().fill(FinePalette.resolve(colorScheme).sidebarTint)

            LinearGradient(
                colors: [
                    FineTheme.glassSheenTop.opacity(sheen),
                    FineTheme.glassSheenMiddle.opacity(sheen),
                    FineTheme.glassTintBottom,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Rectangle()
                .fill(FineTheme.glassEdge)
                .frame(width: 1)
        }
        .ignoresSafeArea()
    }
}

struct QuickSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.25)
                .foregroundStyle(.secondary)
            Spacer()
            trailing
        }
        .padding(.horizontal, FineTheme.sidebarInset)
        .padding(.top, 18)
        .padding(.bottom, 5)
    }
}

// MARK: - 다크 테마

/// 밝은 종이 테마와 짙은 밤 테마가 같은 이름으로 값을 내놓는다.
/// 색을 뷰마다 하드코딩하면 테마를 하나 더 만들 때마다 전부 찾아다녀야 한다.
struct FinePalette {
    let isDark: Bool

    /// 바탕. 밝은 쪽은 종이, 어두운 쪽은 푸른 기가 도는 검정.
    let base: Color
    /// 제목 글자. 배경 위에서 충분히 떠야 한다.
    let ink: Color
    /// 컴포저 유리의 채움과 위/아래 테두리.
    let glassFill: Color
    let glassEdgeTop: Color
    let glassEdgeBottom: Color
    /// 작은 컨트롤의 바탕. 어두운 쪽에서는 검정이 아니라 옅은 흰색이어야 보인다.
    let controlFill: Color
    let divider: Color
    /// 컴포저 뒤에서 은은하게 올라오는 빛. 짙은 블루.
    let bloom: Color
    let shadow: Color
    /// 사이드바는 작업부보다 한 단 어두워야 한다 — 뒤로 물러나는 면이기 때문이다.
    let sidebarTint: Color
    /// 장면 위에 덮는 막. 그림이 밝으면 글자가 묻힌다.
    let sceneScrim: Color
    /// 선택된 대화 줄. 어두운 쪽에서 흰 면은 혼자 튀므로 옅은 회색으로 든다.
    let selectedFill: Color
    let selectedRim: Color

    static let light = FinePalette(
        isDark: false,
        base: Color(red: 0.965, green: 0.962, blue: 0.948),
        ink: Color(red: 0.19, green: 0.21, blue: 0.19),
        glassFill: .white.opacity(0.82),
        glassEdgeTop: .white.opacity(0.85),
        glassEdgeBottom: .white.opacity(0.12),
        controlFill: .black.opacity(0.05),
        divider: .black.opacity(0.07),
        bloom: .clear,
        shadow: Color(red: 0.27, green: 0.30, blue: 0.26).opacity(0.07),
        sidebarTint: .clear,
        sceneScrim: .clear,
        selectedFill: .white.opacity(0.62),
        selectedRim: .white.opacity(0.72)
    )

    /// 짙은 블루 계열. 순검정이 아니라 푸른 기를 남겨야 장면과 바탕이 한 몸으로 읽힌다.
    static let dark = FinePalette(
        isDark: true,
        base: Color(red: 0.027, green: 0.035, blue: 0.063),
        ink: Color(red: 0.90, green: 0.93, blue: 0.99),
        glassFill: Color(red: 0.055, green: 0.085, blue: 0.175).opacity(0.58),
        glassEdgeTop: .white.opacity(0.30),
        glassEdgeBottom: .white.opacity(0.04),
        controlFill: .white.opacity(0.08),
        divider: .white.opacity(0.09),
        bloom: Color(red: 0.16, green: 0.30, blue: 0.72),
        shadow: .black.opacity(0.55),
        sidebarTint: .black.opacity(0.74),
        sceneScrim: .black.opacity(0.30),
        // 거의 검은 패널 위에서는 흰 면이 조명처럼 튄다. 한 단만 들어 올린다.
        selectedFill: .white.opacity(0.10),
        selectedRim: .white.opacity(0.14)
    )

    static func resolve(_ scheme: ColorScheme) -> FinePalette {
        scheme == .dark ? .dark : .light
    }
}

private struct FinePaletteKey: EnvironmentKey {
    static let defaultValue = FinePalette.light
}

extension EnvironmentValues {
    var finePalette: FinePalette {
        get { self[FinePaletteKey.self] }
        set { self[FinePaletteKey.self] = newValue }
    }
}
