import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// A related media group once it's been opened: its items as a carousel of platters, and full screen.
/// Drawn above the whole browsing view, because the cards grow far beyond the row their posters sit
/// in. Every card is one view that stays put while the layer changes; `MediaItemLayout` gives it a
/// frame for each layer, so an animated change grows, shrinks and slides them all together.
struct RelatedMediaGroupCarouselView: View {
    let viewModel: RelatedMediaGroupViewModel
    /// Where the carousel is, in global coordinates. It covers the whole browsing view.
    let globalFrame: CGRect
    var focus: FocusState<BrowsingFocus?>.Binding
    let onExpand: (MediaItem.ID) -> Void

    @Environment(\.viewState) private var layer

    var body: some View {
        let layout = viewModel.carouselLayout(in: globalFrame, layer: layer)
        let isExpanded = viewModel.openCardIsExpanded
        ZStack(alignment: .topLeading) {
            ForEach(layout.drawnIndices, id: \.self) { index in
                let item = viewModel.group.items[index]
                let frame = layout.frame(of: index)
                Button {
                    onExpand(item.id)
                } label: {
                    MediaCardView(viewModel: viewModel.card(for: item))
                        .frame(width: frame.width, height: frame.height)
                }
                .buttonStyle(.borderless)
                // Cards take focus once they've grown, and keep it while they shrink back, so focus
                // doesn't move during the animation. The full-screen actions have it when expanded.
                .disabled(!viewModel.focusIsOnCards || isExpanded)
                .focused(focus, equals: .platter(item.id))
                .onMoveCommand { direction in
                    if direction == .down { onExpand(item.id) }
                }
                .position(x: frame.midX, y: frame.midY)
                .zIndex(index == viewModel.highlightedIndex ? 1 : 0)
                .accessibilityIdentifier("carousel.platter")
                .accessibilityLabel(item.name)
            }

            if isExpanded {
                MediaDetailActionsView(item: viewModel.openItem, focus: focus)
                    .frame(width: globalFrame.width, height: globalFrame.height, alignment: .bottomLeading)
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .frame(width: globalFrame.width, height: globalFrame.height, alignment: .topLeading)
        // Coming back from the sidebar lands on the open card (or its actions), not on whichever card
        // happens to be nearest the sidebar's edge: the sidebar overlaps the open platter.
        .focusSection()
        .defaultFocus(focus, viewModel.openCardFocus, priority: .userInitiated)
    }
}
