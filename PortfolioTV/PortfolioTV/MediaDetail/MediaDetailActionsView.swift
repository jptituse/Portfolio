import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// A card's actions, under its details. They sit above the card rather than in it: the card is a button
/// while it's a platter, and buttons can't contain other buttons. Whoever draws them places them, at
/// `fullScreenDetailsLeadingPadding` and `detailsBottomMargin` from the screen's bottom-leading corner
/// on a full-screen card. Once they're in use, they ask where the item plays from, so Play starts sooner.
struct MediaDetailActionsView<Focus: Hashable>: View {
    let item: MediaItem
    var focus: FocusState<Focus?>.Binding
    /// What focus is on the first action: Play, or Go deeper where there's nothing to play with.
    let focusValue: Focus
    /// Whether they're in use: they take focus, and accessibility sees them. Otherwise they're only
    /// shown, as on a platter, or not at all.
    var isActive = true
    /// Plays the item from the beginning. Without it, Play is unavailable, as on the sample rows.
    var onPlay: (() -> Void)?

    @Environment(\.preparePlayback) private var preparePlayback

    var body: some View {
        HStack(spacing: Metrics.spacing) {
            Button("Play", systemImage: "play.fill") { onPlay?() }
                .disabled(onPlay == nil)
                .focused(focus, equals: focusValue, isFirst: onPlay != nil)
            NavigationLink("Go deeper") {
                MediaDetailView(viewModel: MediaDetailViewModel(item: item))
            }
            .focused(focus, equals: focusValue, isFirst: onPlay == nil)
        }
        .buttonStyle(.glass)
        .disabled(!isActive)
        // Inactive, one element that ignores its buttons, hidden: hiding the buttons alone left them
        // where XCUITest finds them.
        .accessibilityElement(children: isActive ? .contain : .ignore)
        .accessibilityHidden(!isActive)
        .accessibilityIdentifier(isActive ? "detail.fullScreen" : "")
        .onChange(of: isActive && onPlay != nil, initial: true) { _, playable in
            if playable { preparePlayback(item) }
        }
    }
}

private extension View {
    /// Binds focus to `value` only when this is the first action that can take it.
    @ViewBuilder func focused<Value: Hashable>(_ focus: FocusState<Value?>.Binding, equals value: Value, isFirst: Bool) -> some View {
        if isFirst {
            focused(focus, equals: value)
        } else {
            self
        }
    }
}

extension MediaDetailActionsView {
    // Computed: a generic type's nested types can't have stored static properties.
    struct Metrics {
        static var spacing: CGFloat { 32 }
    }
}
