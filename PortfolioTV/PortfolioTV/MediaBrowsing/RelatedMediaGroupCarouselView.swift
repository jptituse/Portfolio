import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// A related media group once it's been opened: its items as a carousel of platters, and full screen.
/// Drawn above the whole browsing view, because the cards grow far beyond the row their posters sit
/// in. Every card is one view that stays put while the layer changes; `RelatedMediaGroupCarouselCardsView`
/// places them all from one animated value, so they grow, shrink and slide together, each platter with
/// its details and actions, which take focus once it's full screen.
struct RelatedMediaGroupCarouselView: View {
    let viewModel: RelatedMediaGroupViewModel
    /// Where the carousel is, in global coordinates. It covers the whole browsing view.
    let globalFrame: CGRect
    var focus: FocusState<BrowsingFocus?>.Binding
    let onExpand: (MediaItem.ID) -> Void

    @Environment(\.viewState) private var layer

    var body: some View {
        // Changes to these come inside the animation that moves the cards, which animates them.
        RelatedMediaGroupCarouselCardsView(
            viewModel: viewModel,
            globalFrame: globalFrame,
            focus: focus,
            onExpand: onExpand,
            layer: layer,
            progress: layer == .preview ? 1 : 0,
            expansion: viewModel.openCardIsExpanded ? 1 : 0,
            openPosition: CGFloat(viewModel.highlightedIndex)
        )
        .frame(width: globalFrame.width, height: globalFrame.height, alignment: .topLeading)
        // Coming back from the sidebar lands on the open card (or its actions), not on whichever card
        // happens to be nearest the sidebar's edge: the sidebar overlaps the open platter.
        .focusSection()
        .defaultFocus(focus, viewModel.openCardFocus, priority: .userInitiated)
    }
}
