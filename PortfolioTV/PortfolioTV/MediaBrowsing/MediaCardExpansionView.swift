import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// A card growing from its poster straight to full screen, drawn above everything it covers, with the
/// full-screen actions once it's there. `MediaCardExpansionViewModel` moves it. It's the same
/// `MediaCardView` a row's platter expands into, with the same actions.
struct MediaCardExpansionView<Focus: Hashable>: View {
    let viewModel: MediaCardExpansionViewModel
    let card: MediaCardViewModel
    /// Where this view is, in global coordinates. It covers the screen.
    let globalFrame: CGRect
    var focus: FocusState<Focus?>.Binding
    /// What focus is while it's on the card's actions.
    let actionsFocus: Focus
    /// Plays the card's item, from the beginning or resuming.
    let onPlay: (MediaItem, PlaybackStart) -> Void

    @Environment(\.prepareDetails) private var prepareDetails

    var body: some View {
        let frame = viewModel.frame(in: globalFrame)
        ZStack(alignment: .topLeading) {
            MediaCardView(viewModel: card)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)

            if viewModel.holdsFocus {
                MediaDetailActionsView(card: card, focus: focus, focusValue: actionsFocus, onPlay: { onPlay(card.item, $0) })
                    .padding(.leading, MediaCardView.Metrics.fullScreenDetailsLeadingPadding)
                    .padding(.bottom, MediaCardView.Metrics.detailsBottomMargin)
                    .frame(width: globalFrame.width, height: globalFrame.height, alignment: .bottomLeading)
                    // They fade out with the details as the card starts to shrink, keeping focus until
                    // the poster takes it back.
                    .opacity(card.showsLabels ? 1 : 0)
                    .transition(.opacity)
            }
        }
        .frame(width: globalFrame.width, height: globalFrame.height, alignment: .topLeading)
        .environment(\.viewState, viewModel.layer)
        .focusSection()
        .defaultFocus(focus, actionsFocus, priority: .userInitiated)
        // As it starts to grow, so the details are in by the time it's full screen.
        .onAppear { prepareDetails(card) }
    }
}
