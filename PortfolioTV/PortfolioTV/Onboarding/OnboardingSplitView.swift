import SwiftUI

/// A screen split in two: what to fill in on the leading half, and a picture on the trailing half,
/// which runs to the edges of the screen.
struct OnboardingSplitView<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(maxWidth: Metrics.formWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The trailing half is sized first and the picture drawn over it, so a picture that fills
            // its space (such as a server's splash image) can't take room from the leading half.
            Color.clear
                .overlay { trailing }
                .background(.white.opacity(Metrics.trailingTint))
                .clipped()
                .ignoresSafeArea()
        }
    }
}

extension OnboardingSplitView {
    struct Metrics {
        static var formWidth: CGFloat { 760 }
        static var trailingTint: Double { 0.06 }
    }
}
