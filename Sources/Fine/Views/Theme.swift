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
    var body: some View {
        ZStack(alignment: .trailing) {
            Rectangle()
                .fill(.ultraThinMaterial)

            LinearGradient(
                colors: [
                    FineTheme.glassSheenTop,
                    FineTheme.glassSheenMiddle,
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
