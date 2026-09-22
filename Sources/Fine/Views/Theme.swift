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

    static let workspace = Color(nsColor: .textBackgroundColor)
    static let divider = Color.black.opacity(0.07)
    static let hoverFill = Color.black.opacity(0.04)
    static let selectedFill = Color.white.opacity(0.62)
    static let selectedRim = Color.white.opacity(0.72)
    static let controlFill = Color.black.opacity(0.05)
    static let pickerRailFill = Color.black.opacity(0.018)
    static let overlayScrim = Color.black.opacity(0.06)
    static let overlayShadow = Color.black.opacity(0.14)
    static let overlayCornerRadius: CGFloat = 12
    static let glassSheenTop = Color.white.opacity(0.30)
    static let glassSheenMiddle = Color.white.opacity(0.10)
    static let glassTintBottom = Color(nsColor: .windowBackgroundColor).opacity(0.08)
    static let glassEdge = Color.black.opacity(0.08)
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
