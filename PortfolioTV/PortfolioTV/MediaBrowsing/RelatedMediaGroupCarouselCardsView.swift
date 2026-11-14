import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// The cards of an open related media group, and their artwork, placed by `MediaItemLayout` on every
/// frame of a motion. SwiftUI animates the three numbers the layout takes as one value, so on each frame
/// every card and its artwork are placed from the same point of the motion, and the artwork covers the
/// part of its card on screen. Animating each card's frame and its artwork's on their own, on an Apple
/// TV the open card started a few frames behind its neighbors, and its artwork ran ahead of it with the
/// poster showing around it; the simulator showed neither.
struct RelatedMediaGroupCarouselCardsView: View, @preconcurrency Animatable {
    let viewModel: RelatedMediaGroupViewModel
    /// Where the carousel is, in global coordinates. It covers the whole browsing view.
    let globalFrame: CGRect
    var focus: FocusState<BrowsingFocus?>.Binding
    let onExpand: (MediaItem.ID) -> Void
    /// The layer the row's hierarchy is in, which sets the cards' forms: posters, platters or full
    /// screen.
    let layer: ViewState
    /// How far the cards have grown from their posters: 0 on them, 1 open.
    var progress: CGFloat
    /// How far the open card has grown to fill the screen.
    var expansion: CGFloat
    /// Where the open card is in the row, between two indices while the row slides.
    var openPosition: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(progress, AnimatablePair(expansion, openPosition)) }
        set {
            progress = newValue.first
            expansion = newValue.second.first
            openPosition = newValue.second.second
        }
    }

    var body: some View {
        let layout = layout
        let isExpanded = viewModel.openCardIsExpanded
        ZStack(alignment: .topLeading) {
            ForEach(layout.drawnIndices, id: \.self) { index in
                card(at: index, in: layout, isExpanded: isExpanded)
            }
            ForEach(layout.drawnIndices.filter { !layout.waitsOffScreen($0) }, id: \.self) { index in
                actions(at: index, in: layout, isExpanded: isExpanded)
            }
        }
        .frame(width: globalFrame.width, height: globalFrame.height, alignment: .topLeading)
    }

    /// Where everything is at this point of the motion.
    private var layout: MediaItemLayout {
        var layout = viewModel.carouselLayout(in: globalFrame, layer: layer)
        layout.progress = progress
        layout.expansion = expansion
        layout.openPosition = openPosition
        return layout
    }

    private func card(at index: Int, in layout: MediaItemLayout, isExpanded: Bool) -> some View {
        let item = viewModel.group.items[index]
        let frame = layout.frame(of: index)
        let artworkFrame = layout.artworkFrame(of: index).offsetBy(dx: -frame.minX, dy: -frame.minY)
        return Button {
            onExpand(item.id)
        } label: {
            MediaCardView(viewModel: viewModel.card(for: item), artworkFrame: artworkFrame)
                .frame(width: frame.width, height: frame.height)
                // Cards waiting off screen stay posters.
                .environment(\.viewState, layout.waitsOffScreen(index) ? .root : layer)
        }
        .buttonStyle(MediaCardButtonStyle())
        // Cards take focus once they've grown, and keep it while they shrink back, so focus doesn't
        // move during the animation. The full-screen actions have it when expanded.
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

    /// A card's actions, under its details, as on a full-screen card. A card is a button, which can't hold
    /// others, so they're drawn above it, moving with it. They're on every platter, but only take focus,
    /// and are only seen by accessibility, once the open card is full screen: on a platter, focus is on
    /// the platter.
    private func actions(at index: Int, in layout: MediaItemLayout, isExpanded: Bool) -> some View {
        let item = viewModel.group.items[index]
        let frame = layout.frame(of: index)
        let takesFocus = isExpanded && index == viewModel.highlightedIndex
        return MediaDetailActionsView(item: item, focus: focus, focusValue: .detail(item.id), isActive: takesFocus)
            .padding(.leading, layout.detailsLeadingPadding(of: index))
            .padding(.bottom, MediaCardView.Metrics.detailsBottomMargin)
            .frame(width: frame.width, height: frame.height, alignment: .bottomLeading)
            .position(x: frame.midX, y: frame.midY)
            .opacity(viewModel.card(for: item).actionsOpacity(in: layer))
            .zIndex(2)
    }
}
