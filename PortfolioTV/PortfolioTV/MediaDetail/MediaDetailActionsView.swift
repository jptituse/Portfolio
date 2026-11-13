import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// The full-screen card's actions. They sit above the card rather than in it: the card is a button
/// while it's a platter, and buttons can't contain other buttons.
struct MediaDetailActionsView<Focus: Hashable>: View {
    let item: MediaItem
    var focus: FocusState<Focus?>.Binding
    /// What focus is while it's on the actions.
    let focusValue: Focus

    var body: some View {
        HStack(spacing: Metrics.spacing) {
            Button("Play", systemImage: "play.fill") {}
                .disabled(true)  // Playback comes with #15.
            NavigationLink("Go deeper") {
                MediaDetailView(viewModel: MediaDetailViewModel(item: item))
            }
            .focused(focus, equals: focusValue)
        }
        .padding(.leading, MediaCardView.Metrics.fullScreenDetailsLeadingPadding)
        .padding(.bottom, Metrics.bottomPadding)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.fullScreen")
    }
}

extension MediaDetailActionsView {
    // Computed: a generic type's nested types can't have stored static properties.
    struct Metrics {
        static var spacing: CGFloat { 32 }
        static var bottomPadding: CGFloat { 96 }
    }
}
