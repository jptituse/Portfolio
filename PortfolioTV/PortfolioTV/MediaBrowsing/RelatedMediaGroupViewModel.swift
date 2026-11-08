import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// A related media group as tvOS shows it: a row of posters that opens into a carousel. Both views
/// watch this, so it holds what they share: which card is highlighted, whether the open cards hold
/// focus, one card per item, and where each poster is.
///
/// Focus staying on a poster widens it to show its landscape thumbnail. The highlighted poster stays
/// wide while the row is open, so closing lands on the wide poster.
@MainActor
@Observable
final class RelatedMediaGroupViewModel: Identifiable {
    let group: RelatedMediaGroup

    /// The card the row is on: its focused poster, or its open platter.
    private(set) var highlightedItem: MediaItem.ID?
    /// True while opening: the open card starts on its focused poster, which tvOS draws lifted.
    var startsLifted = false
    /// Whether the open cards hold focus. The focused poster keeps it while the cards grow; they take
    /// it over once they're in place.
    var focusIsOnCards = false
    /// True for a moment before a poster widens: the row adds room at its end, which the poster then
    /// grows into. A scroll view can't scroll into width that's still animating in, so without it the
    /// last poster would run off the screen instead of pushing the others aside.
    private(set) var isMakingRoomToExtend = false

    @ObservationIgnored private var cards: [MediaItem.ID: MediaCardViewModel] = [:]
    /// Where each poster is, in global coordinates, so the open cards can start and end exactly on top
    /// of them. Not observed: posters report their frames on every scroll, and that shouldn't redraw
    /// anything. They're read when the row opens or closes.
    @ObservationIgnored private var globalPosterFrames: [MediaItem.ID: CGRect] = [:]
    @ObservationIgnored private var idleTimer: Task<Void, Never>?
    @ObservationIgnored private let idleDelay: Duration

    init(group: RelatedMediaGroup, idleDelay: Duration = RelatedMediaGroupPosterView.Metrics.idleDelay) {
        self.group = group
        self.idleDelay = idleDelay
    }

    var id: RelatedMediaGroup.ID { group.id }

    /// The item's card. A poster and the card that grows out of it share one, so they always agree.
    func card(for item: MediaItem) -> MediaCardViewModel {
        if let card = cards[item.id] { return card }
        let card = MediaCardViewModel(item: item)
        cards[item.id] = card
        return card
    }

    var highlightedCard: MediaCardViewModel? {
        highlightedItem.flatMap { cards[$0] }
    }

    var highlightedIndex: Int {
        group.items.firstIndex { $0.id == highlightedItem } ?? 0
    }

    /// The wide poster, if there is one.
    var extendedItem: MediaItem.ID? {
        highlightedCard?.isExtended == true ? highlightedItem : nil
    }

    func setLabelsShowing(_ isShowing: Bool) {
        for item in group.items {
            let card = card(for: item)
            if card.showsLabels != isShowing { card.showsLabels = isShowing }
        }
    }

    func posterMoved(_ item: MediaItem.ID, to globalFrame: CGRect) {
        globalPosterFrames[item] = globalFrame
    }

    // MARK: Focus

    /// A poster got focus: it's now the highlighted card, and it widens if focus stays on it.
    func posterFocused(_ item: MediaItem.ID) {
        idleTimer?.cancel()
        withAnimation(RelatedMediaGroupPosterView.Metrics.extend) { moveHighlight(to: item) }
        if highlightedCard?.isExtended != true { startIdleTimer(for: item) }
    }

    /// Focus left the row's posters: nothing in it is highlighted any more.
    func focusLeft() {
        idleTimer?.cancel()
        withAnimation(RelatedMediaGroupPosterView.Metrics.extend) { moveHighlight(to: nil) }
    }

    // MARK: Opening

    func willOpen(on item: MediaItem.ID) {
        idleTimer?.cancel()
        isMakingRoomToExtend = false
        moveHighlight(to: item)
        startsLifted = true
    }

    /// Widens the highlighted poster while it's hidden under its card, so closing lands on it.
    func extendHighlightedPoster() {
        highlightedCard?.isExtended = true
    }

    /// Makes another platter the highlighted card, moving the wide poster along with it.
    func highlightPlatter(_ item: MediaItem.ID) {
        moveHighlight(to: item)
        extendHighlightedPoster()
    }

    // MARK: The open carousel

    /// The item at the center of the carousel.
    var openItem: MediaItem { group.items[highlightedIndex] }

    var openCard: MediaCardViewModel { card(for: openItem) }

    /// Whether the open card has grown to fill the screen.
    var openCardIsExpanded: Bool { openCard.viewState == .root }

    /// Where focus lands when it comes into the carousel: the open card, or its actions once it has
    /// expanded.
    var openCardFocus: BrowsingFocus {
        openCardIsExpanded ? .detail(openItem.id) : .platter(openItem.id)
    }

    /// Where each card goes in a carousel at `globalFrame`, while the browsing view is at `layer`.
    func carouselLayout(in globalFrame: CGRect, layer: ViewState) -> MediaItemLayout {
        typealias Metrics = RelatedMediaGroupCarouselView.Metrics
        return MediaItemLayout(
            size: globalFrame.size,
            itemCount: group.items.count,
            currentIndex: highlightedIndex,
            posterFrames: posterFrames(relativeTo: globalFrame.origin),
            liftedIndex: startsLifted ? highlightedIndex : nil,
            liftScale: openCard.isExtended ? Metrics.extendedPosterLiftScale : Metrics.posterLiftScale,
            layer: layer,
            openCardState: openCard.viewState
        )
    }

    // MARK: Private

    /// The poster frames by index in the row, measured from `origin` instead of the global origin.
    private func posterFrames(relativeTo origin: CGPoint) -> [Int: CGRect] {
        var frames: [Int: CGRect] = [:]
        for (index, item) in group.items.enumerated() {
            if let frame = globalPosterFrames[item.id] {
                frames[index] = frame.offsetBy(dx: -origin.x, dy: -origin.y)
            }
        }
        return frames
    }

    private func moveHighlight(to item: MediaItem.ID?) {
        guard item != highlightedItem else { return }
        isMakingRoomToExtend = false
        highlightedCard?.isFocused = false
        highlightedCard?.isExtended = false
        highlightedItem = item
        if let item, let target = group.items.first(where: { $0.id == item }) {
            card(for: target).isFocused = true
        }
    }

    private func startIdleTimer(for item: MediaItem.ID) {
        idleTimer = Task { [weak self, idleDelay] in
            try? await Task.sleep(for: idleDelay)
            guard !Task.isCancelled, let self, self.highlightedItem == item else { return }
            self.isMakingRoomToExtend = true
            try? await Task.sleep(for: RelatedMediaGroupPosterView.Metrics.makingRoomDelay)
            guard !Task.isCancelled, self.highlightedItem == item else { return }
            // FIXME: Start the item's trailer here once trailers exist, and keep it playing as the card
            // grows into its platter and on to full screen.
            withAnimation(RelatedMediaGroupPosterView.Metrics.extend) {
                self.highlightedCard?.isExtended = true
                self.isMakingRoomToExtend = false
            }
        }
    }
}
