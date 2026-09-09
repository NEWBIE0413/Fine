import SwiftUI

/// Bundled vector template marks: the same quiet ink for every harness.
struct HarnessLogo: View {
    let harness: QuickHarness

    var body: some View {
        Image(harness.rawValue, bundle: .module)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 12, height: 12)
            .foregroundStyle(.primary.opacity(0.58))
            .frame(width: 15, height: 15)
            .help(harness.title)
            .accessibilityLabel(harness.title)
    }
}
