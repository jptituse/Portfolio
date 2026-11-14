import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// A card's actions, under its details. They sit above the card rather than in it: the card is a button
/// while it's a platter, and buttons can't contain other buttons. Whoever draws them places them, at
/// `fullScreenDetailsLeadingPadding` and `detailsBottomMargin` from the screen's bottom-leading corner
/// on a full-screen card.
struct MediaDetailActionsView<Focus: Hashable>: View {
    let item: MediaItem
    var focus: FocusState<Focus?>.Binding
    /// What focus is while it's on the actions.
    let focusValue: Focus
    /// Whether they're in use: they take focus, and accessibility sees them. Otherwise they're only
    /// shown, as on a platter, or not at all.
    var isActive = true

    var body: some View {
        HStack(spacing: Metrics.spacing) {
            Button("Play", systemImage: "play.fill") {}
                .disabled(true)  // Playback comes with #15.
            NavigationLink("Go deeper") {
                MediaDetailView(viewModel: MediaDetailViewModel(item: item))
            }
            .focused(focus, equals: focusValue)
        }
        .buttonStyle(.glass)
        .disabled(!isActive)
        // Inactive, one element that ignores its buttons, hidden: hiding the buttons alone left them
        // where XCUITest finds them.
        .accessibilityElement(children: isActive ? .contain : .ignore)
        .accessibilityHidden(!isActive)
        .accessibilityIdentifier(isActive ? "detail.fullScreen" : "")
    }
}

extension MediaDetailActionsView {
    // Computed: a generic type's nested types can't have stored static properties.
    struct Metrics {
        static var spacing: CGFloat { 32 }
    }
}
