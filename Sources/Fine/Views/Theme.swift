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
    static let compactControlRadius: CGFloat = 7
    static let composerCornerRadius: CGFloat = 14
    static let homeContentWidth: CGFloat = 680

    static let workspace = Color(nsColor: .textBackgroundColor)
    static let divider = Color.black.opacity(0.07)
    static let hoverFill = Color.black.opacity(0.04)
    static let selectedFill = Color.white.opacity(0.62)
    static let selectedRim = Color.white.opacity(0.72)
    static let controlFill = Color.black.opacity(0.05)
    static let glassSheenTop = Color.white.opacity(0.30)
    static let glassSheenMiddle = Color.white.opacity(0.10)
    static let glassTintBottom = Color(nsColor: .windowBackgroundColor).opacity(0.08)
    static let glassEdge = Color.black.opacity(0.08)
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
