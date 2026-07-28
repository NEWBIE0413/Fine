import SwiftUI

enum SidebarMetrics {
    static let rowCornerRadius: CGFloat = 10
    static let rowVerticalPadding: CGFloat = 8
    static let rowHorizontalPadding: CGFloat = 12
    static let iconSize: CGFloat = 13
    static let iconFrame: CGFloat = 16
}

struct QuickSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.3)
                .foregroundColor(.secondary.opacity(0.95))
            Spacer()
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }
}
