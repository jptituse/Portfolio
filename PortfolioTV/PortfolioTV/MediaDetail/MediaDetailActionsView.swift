import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// The full-screen card's actions. They sit above the card rather than in it: the card is a button
/// while it's a platter, and buttons can't contain other buttons.
struct MediaDetailActionsView: View {
    let item: MediaItem
    var focus: FocusState<BrowsingFocus?>.Binding

    var body: some View {
        HStack(spacing: Metrics.spacing) {
            Button("Play", systemImage: "play.fill") {}
                .disabled(true)  // Playback comes with #15.
            NavigationLink("Go deeper") {
                MediaDetailView(viewModel: MediaDetailViewModel(item: item))
            }
            .focused(focus, equals: .detail(item.id))
        }
        .padding(.leading, MediaCardView.Metrics.fullScreenDetailsLeadingPadding)
        .padding(.bottom, Metrics.bottomPadding)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.fullScreen")
    }
}

extension MediaDetailActionsView {
    struct Metrics {
        static let spacing: CGFloat = 32
        static let bottomPadding: CGFloat = 96
    }
}
