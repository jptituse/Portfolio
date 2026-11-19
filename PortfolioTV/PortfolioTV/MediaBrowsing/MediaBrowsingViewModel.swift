import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// The groups being browsed, which one's row is open and which layer the browsing view is in, and the
/// order things happen as cards move between layers. Opening puts the cards exactly on top of their
/// posters (which hide underneath) and then enters `.preview`; closing returns to `.root`, shrinking
/// the cards back onto the posters before showing them again. Setting the previewed card to `.root`
/// expands it to fill the screen.
///
/// Focus never moves while cards are moving: a tvOS focus update at the start of an animation stalls
/// its first frames. It moves to the cards once they've grown, and back to the posters once they've
/// shrunk. `@FocusState` can only live in a view, so the view passes in its binding.
///
/// Labels stay out of the motion: as a row opens or closes, the labels on show fade out at once, and
/// the ones for the new layer fade in only after the cards have stopped.
@MainActor
@Observable
final class MediaBrowsingViewModel {
    typealias Focus = FocusState<BrowsingFocus?>.Binding

    let groups: [RelatedMediaGroupViewModel]
    /// The layer the browsing view is in. Every view inside it inherits it.
    private(set) var viewState: ViewState = .root
    /// The group whose row is open as a carousel.
    private(set) var openGroup: RelatedMediaGroupViewModel?
    /// The poster focus left in the row it was in before, where it lands going back to that row,
    /// rather than on whichever poster is nearest: going down from the end of a long row to a short one
    /// and back up returns to where it was. Focus moving on from the next row too forgets it.
    private(set) var posterLeftBehind: BrowsingFocus?

    @ObservationIgnored private var focusedGroup: RelatedMediaGroupViewModel?
    @ObservationIgnored private var closingGroup: RelatedMediaGroupViewModel?
    /// Set while focus returns from the cards to a poster, when it's briefly on nothing at all.
    @ObservationIgnored private var isReturningFocusToPoster = false
    /// Set when Back comes while the cards are still growing: they close once they've grown. Turning
    /// round partway, a row of wide cards' pictures would jump, since they move one way opening and
    /// another closing.
    @ObservationIgnored private var closesOnceGrown = false

    @ObservationIgnored private let onPlay: PlayAction?

    /// - Parameters:
    ///   - images: where the items' artwork comes from.
    ///   - userDataUpdates: where the user got to in what they've played since the items loaded.
    ///   - onPlay: plays an item, from the beginning or resuming. Without it, nothing plays.
    init(
        groups: [RelatedMediaGroup],
        images: (any MediaImageResolver)? = nil,
        userDataUpdates: UserDataUpdates? = nil,
        onPlay: PlayAction? = nil
    ) {
        self.groups = groups.map { RelatedMediaGroupViewModel(group: $0, images: images, userDataUpdates: userDataUpdates) }
        self.onPlay = onPlay
    }

    /// Plays an item as a card's actions ask, if anything plays. The card's detail view is behind the
    /// player already.
    var playsFromCards: ((MediaItem, PlaybackStart) -> Void)? {
        onPlay.map { play in { play($0, $1, nil) } }
    }

    /// Sets the screen the cards' artwork is fetched for: its scale, and its size in points, which is the
    /// size of a platter's artwork.
    func setScreen(scale: CGFloat, size: CGSize) {
        groups.forEach { $0.setScreen(scale: scale, size: size) }
    }

    func isOpen(_ group: RelatedMediaGroupViewModel) -> Bool {
        openGroup === group
    }

    /// Whether the open cards hold focus, so the posters behind them mustn't take it.
    var cardsHoldFocus: Bool {
        openGroup?.focusIsOnCards == true
    }

    /// Where focus lands coming into `group`'s row from elsewhere: the poster it left there, if it has
    /// just come from that row, and otherwise wherever tvOS puts it.
    func posterToComeBack(to group: RelatedMediaGroupViewModel) -> BrowsingFocus? {
        guard case .poster(_, let groupID) = posterLeftBehind, groupID == group.id else { return nil }
        return posterLeftBehind
    }

    /// Where focus falls back to once the cards give it up: the poster they closed on.
    var posterToReturnTo: BrowsingFocus? {
        guard let openGroup, let item = openGroup.highlightedItem else { return nil }
        return .poster(item, group: openGroup.id)
    }

    /// The item a focused poster plays when it's selected, rather than opening its row: in a row of
    /// what's in progress, such as Continue Watching, if anything plays.
    func itemPlayedOnSelect(at focus: BrowsingFocus?) -> MediaItem? {
        guard onPlay != nil, case .poster(let item, let groupID) = focus,
              let group = groups.first(where: { $0.id == groupID }), group.isInProgress else { return nil }
        return group.group.items.first { $0.id == item }
    }

    /// Where focus belongs while the open card fills the screen and its actions hold focus: on them.
    var fullScreenActions: BrowsingFocus? {
        guard let openGroup, openGroup.focusIsOnCards, openGroup.highlightedCard?.viewState == .root,
              let item = openGroup.highlightedItem else { return nil }
        return .detail(item)
    }

    /// Whether Menu steps back through the open row. Otherwise it does what it always does.
    var canStepBack: Bool {
        openGroup != nil
    }

    /// A poster was selected: its row opens on it. In a row of what's in progress, such as Continue
    /// Watching, it plays instead, from where it was left, and the row opens on its full-screen card
    /// behind the player as it closes.
    func select(_ item: MediaItem, in group: RelatedMediaGroupViewModel) {
        guard openGroup == nil else { return }
        if group.isInProgress, let onPlay {
            onPlay(item, .resuming) { [weak self, weak group] in
                guard let self, let group else { return }
                self.openOnFullScreenCard(item.id, in: group)
            }
            return
        }
        group.willOpen(on: item.id)
        openGroup = group
    }

    /// Opens `group`'s row straight onto `item`'s full-screen card, skipping the platter. The card's own
    /// `viewState` is set to `.root` while it's still a poster, which changes nothing at the `.root`
    /// layer; entering `.preview` then takes it straight to full screen. Back steps back to its platter,
    /// as from any full-screen card.
    func openOnFullScreenCard(_ item: MediaItem.ID, in group: RelatedMediaGroupViewModel) {
        guard openGroup == nil else { return }
        group.willOpen(on: item)
        group.highlightedCard?.viewState = .root
        openGroup = group
    }

    /// Runs once the cards are on screen on top of their posters: grows them into the preview.
    func growIntoPreview(focus: Focus) {
        guard let group = openGroup else { return }
        withAnimation(MediaCardView.Metrics.labelFadeOut) { group.setLabelsShowing(false) }
        withAnimation(RelatedMediaGroupCarouselView.Metrics.layerChange, completionCriteria: .logicallyComplete) {
            viewState = .preview
        } completion: { [self] in
            guard let item = group.highlightedItem, viewState == .preview else { return }
            // Back came while they grew: they go straight back, onto the poster, which still has focus
            // and so is still lifted.
            if closesOnceGrown {
                closesOnceGrown = false
                close(group, on: item, focus: focus)
                return
            }
            // From here on the poster frame means the resting one: closing shrinks back to it, and the
            // poster lifts again on its own when it gets focus back. Not before: the cards are placed
            // from it on every frame, and they'd start from the smaller, resting poster.
            group.startsLifted = false
            // The cards have grown: now focus can move to the open one, and the details can appear.
            // Only now does the poster under the open card widen, so closing lands on a wide poster.
            // Widening it first would switch the card to its landscape art at once, with no fade.
            group.extendHighlightedPoster()
            group.focusIsOnCards = true
            // A card that went straight to full screen gives focus to its actions.
            moveFocus(focus, to: group.highlightedCard?.viewState == .root ? .detail(item) : .platter(item))
            withAnimation(MediaCardView.Metrics.labelFadeIn) { group.setLabelsShowing(true) }
        }
    }

    func focusMoved(to newValue: BrowsingFocus?) {
        switch newValue {
        case .poster(let item, let groupID):
            guard openGroup == nil, let group = groups.first(where: { $0.id == groupID }) else { return }
            isReturningFocusToPoster = false
            if focusedGroup !== group {
                leavePosters()
            }
            focusedGroup = group
            group.posterFocused(item)
        case .platter(let item):
            // Moving between platters makes the newly focused one the open card; the row slides.
            guard let group = openGroup, viewState == .preview, group.highlightedCard?.viewState == .preview, item != group.highlightedItem else { return }
            withAnimation(RelatedMediaGroupCarouselView.Metrics.platterSlide) { group.highlightPlatter(item) }
        case .detail:
            break
        case nil:
            guard openGroup == nil, !isReturningFocusToPoster else { return }
            leavePosters()
            focusedGroup = nil
        }
    }

    /// Focus left the row it was in, for another row or for something else, such as Home's banner: it
    /// remembers the poster it was on there.
    private func leavePosters() {
        guard let group = focusedGroup else { return }
        if let item = group.highlightedItem {
            posterLeftBehind = .poster(item, group: group.id)
        }
        group.focusLeft()
    }

    func expand(_ item: MediaItem.ID, focus: Focus) {
        // The open card keeps focus while it shrinks back, but it can't expand from there.
        guard let group = openGroup, viewState == .preview, group.highlightedCard?.viewState == .preview else { return }
        group.highlightPlatter(item)
        withAnimation(RelatedMediaGroupCarouselView.Metrics.layerChange) { group.highlightedCard?.viewState = .root }
        // The platter that had focus can't keep it, so focus moves to the full-screen actions.
        moveFocus(focus, to: .detail(item))
    }

    func stepBack(focus: Focus) {
        guard let group = openGroup, let item = group.highlightedItem, viewState == .preview else { return }
        // Still growing: they close once they've grown.
        guard group.focusIsOnCards else {
            closesOnceGrown = true
            return
        }
        if group.highlightedCard?.viewState == .root {
            withAnimation(RelatedMediaGroupCarouselView.Metrics.layerChange) { group.highlightedCard?.viewState = .preview }
            moveFocus(focus, to: .platter(item))
        } else {
            close(group, on: item, focus: focus)
        }
    }

    /// Runs once the posters are back on screen: they've landed, so their titles can fade in.
    func groupDidClose() {
        withAnimation(MediaCardView.Metrics.labelFadeIn) { closingGroup?.setLabelsShowing(true) }
        closingGroup = nil
    }

    private func close(_ group: RelatedMediaGroupViewModel, on item: MediaItem.ID, focus: Focus) {
        closingGroup = group
        isReturningFocusToPoster = true
        withAnimation(MediaCardView.Metrics.labelFadeOut) { group.setLabelsShowing(false) }
        // Only once the cards are on their posters: removing them while they're still moving makes them
        // jump onto the posters.
        withAnimation(RelatedMediaGroupCarouselView.Metrics.layerChange, completionCriteria: .removed) {
            viewState = .root
        } completion: { [self] in
            // The cards are back on their posters. The chosen poster gets focus before the cards
            // go: removing them first lets tvOS pick a poster itself, lighting up the row's first
            // one for a moment.
            group.focusIsOnCards = false
            Task { @MainActor in
                focus.wrappedValue = .poster(item, group: group.id)
                openGroup = nil
            }
        }
    }

    /// Focus can only move to a view once it's on screen and enabled, so this waits for the next update.
    private func moveFocus(_ focus: Focus, to target: BrowsingFocus) {
        Task { @MainActor in focus.wrappedValue = target }
    }
}
