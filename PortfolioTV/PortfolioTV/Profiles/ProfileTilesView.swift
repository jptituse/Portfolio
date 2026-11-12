import SwiftUI

/// A picker's tiles in a row: centered while they fit, scrolling sideways once they don't.
struct ProfileTilesView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Metrics.spacing) {
                content
            }
            .padding(.vertical, Metrics.verticalPadding)
        }
        .scrollClipDisabled()
        .defaultScrollAnchor(.center, for: .alignment)
    }
}

extension ProfileTilesView {
    struct Metrics {
        static var spacing: CGFloat { 48 }
        static var verticalPadding: CGFloat { 40 }
    }
}
