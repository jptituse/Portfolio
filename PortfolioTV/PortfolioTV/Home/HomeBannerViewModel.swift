import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// Home's banner: the items it goes through, which one is showing, and the move from one to the next,
/// which it drives.
///
/// Moving on, the banner's text and buttons fade out first. Then the next banner slides in over the
/// one showing, which stays put. The next one's artwork doesn't move: the banner's edge sweeps across
/// it from the right, uncovering it in place, as a platter uncovers its artwork in the carousel. Once
/// it has, the text and buttons fade back in, for the new item. Going back, the previous banner comes
/// in the same way from the left. Focus comes back to the button it was on.
///
/// Right and › go round from the last banner to the first, and Left stops at the first, where it
/// brings in the sidebar. It moves on by itself every `interval` while it's advancing, counting again
/// from each move, until it reaches the last.
@MainActor
@Observable
final class HomeBannerViewModel {
    private(set) var items: [MediaItem] = []
    /// The banner showing.
    private(set) var index = 0
    /// The banner sliding in over the one showing, while it does.
    private(set) var incomingIndex: Int?
    /// Whether the incoming banner has slid all the way in.
    private(set) var incomingHasSlidIn = false
    /// Whether the incoming banner comes in from the left, going back, rather than from the right.
    private(set) var incomingComesFromLeading = false
    /// Whether the text and buttons show. They fade out before a banner slides in, and come back once
    /// it has.
    private(set) var showsLabels = true
    /// Whether the banner is its item's full-screen detail view: its details where a full-screen card has
    /// them, and the card's actions in place of its buttons. Info opens it and Back closes it, moving the
    /// details and cross-fading the buttons.
    private(set) var showsDetails = false
    /// Whether the details are away from the banner's own place: moving there, there, or moving back.
    /// Only then can the actions take focus: hidden, they still drew focus moving between the banner's
    /// buttons to what catches Left and Right. And the page can't scroll: focus moves between Info and
    /// the actions while they're low on the screen, and tvOS scrolled the page to show them.
    private(set) var detailsAreAway = false
    /// Whether the details are moving, either way. Focus stays on the button it was on through a move,
    /// faded out to `focusableOpacity`, so the banner's buttons and the actions both take focus then.
    private(set) var detailsAreMoving = false
    /// Whether the banner is counting down to moving on by itself, which the page indicator shows.
    private(set) var isCountingDown = false
    /// Goes up each time the countdown starts again from the beginning.
    private(set) var countdown = 0
    /// How long a banner shows before the next one slides in.
    let interval: Duration
    /// The button focus was on last, where it lands coming back to the banner: from the rows, or once a
    /// banner has moved in.
    private(set) var lastButton: HomeFocus = .bannerInfo

    @ObservationIgnored private let images: (any MediaImageResolver)?
    @ObservationIgnored private let pipeline: ImagePipeline
    @ObservationIgnored private var cards: [MediaItem.ID: MediaCardViewModel] = [:]
    @ObservationIgnored private var screen: (scale: CGFloat, size: CGSize)?
    @ObservationIgnored private var isAdvancing = false
    @ObservationIgnored private var advancing: Task<Void, Never>?
    /// What to do once the text and buttons are back, after the move under way.
    @ObservationIgnored private var whenLabelsReturn: [() -> Void] = []

    /// - Parameter interval: how long a banner shows before the next one slides in.
    // FIXME: Play each item's trailer, and move on once it ends, once trailers exist.
    init(images: (any MediaImageResolver)?, pipeline: ImagePipeline = .shared, interval: Duration = .seconds(8)) {
        self.images = images
        self.pipeline = pipeline
        self.interval = interval
    }

    var current: MediaItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    /// The banners drawn: the one showing, and the one sliding in over it.
    var layers: [MediaItem] {
        [current, incomingIndex.map { items[$0] }].compactMap(\.self)
    }

    /// Whether `item` is the banner sliding in, rather than the one showing.
    func isIncoming(_ item: MediaItem) -> Bool {
        incomingIndex.map { items[$0].id == item.id } ?? false
    }

    /// Whether nothing is moving, so the banner can open its item's details.
    var isIdle: Bool {
        incomingIndex == nil && showsLabels && !showsDetails
    }

    /// The items to go through. The banner stays on the item it shows if that's still among them.
    func setItems(_ items: [MediaItem]) {
        guard items != self.items else { return }
        let showing = current?.id
        self.items = items
        index = items.firstIndex { $0.id == showing } ?? 0
        incomingIndex = nil
        incomingHasSlidIn = false
        warmNextArtwork()
        // Home starts counting down before its items arrive, with nowhere to go yet.
        restartAdvancing()
    }

    /// Sets the screen the artwork is fetched for: its scale, and its size in points, which is the
    /// banner's.
    func setScreen(scale: CGFloat, size: CGSize) {
        screen = (scale, size)
        cards.values.forEach(setArtworkSizes)
        warmNextArtwork()
    }

    /// The item's card: where its artwork is, and the full-screen card its Info button opens, which
    /// shows the very same artwork.
    func card(for item: MediaItem) -> MediaCardViewModel {
        if let card = cards[item.id] { return card }
        let card = MediaCardViewModel(item: item, images: images)
        setArtworkSizes(of: card)
        cards[item.id] = card
        return card
    }

    // MARK: Focus

    /// Focus came to one of the banner's buttons.
    func buttonFocused(_ button: HomeFocus) {
        if lastButton != button { lastButton = button }
    }

    // MARK: Moving on

    /// Whether Right and › move to another banner: with more than one, going round from the last to the
    /// first.
    var hasNext: Bool {
        items.count > 1
    }

    /// Whether there's a banner before the one showing. On the first, Left brings in the sidebar.
    var hasPrevious: Bool {
        index > 0
    }

    /// Slides the next banner in from the right, the first after the last. `then` runs once its text and
    /// buttons are back, or at once if there's no other banner; during another move, once that one is
    /// over.
    func next(then completion: @escaping () -> Void = {}) {
        go(by: 1, then: completion)
    }

    /// Slides the previous banner in from the left, as `next(then:)` does the next.
    func previous(then completion: @escaping () -> Void = {}) {
        go(by: -1, then: completion)
    }

    private func go(by step: Int, then completion: @escaping () -> Void) {
        // Not while its details show.
        guard !detailsAreAway else {
            completion()
            return
        }
        guard incomingIndex == nil else {
            whenLabelsReturn.append(completion)
            return
        }
        guard step > 0 ? hasNext : hasPrevious else {
            completion()
            return
        }
        whenLabelsReturn.append(completion)
        move(to: (index + step + items.count) % items.count, fromLeading: step < 0)
    }

    /// Whether Left and Right from the buttons are caught to move between banners: while there's one
    /// that way and the banner shows its own buttons, except for a moment while focus returns from
    /// catching them.
    var catchesEdges: Bool {
        isCatchingEdges && !detailsAreAway
    }
    private var isCatchingEdges = true

    /// Whether the banner's own buttons take focus: not while its details show and are still.
    var buttonsTakeFocus: Bool {
        !showsDetails || detailsAreMoving
    }

    /// Hands focus back from what caught Left or Right: stops catching them, so focus leaves the edge,
    /// runs `then` to put focus on a button, and catches them again once it has.
    func releaseEdges(then completion: @escaping () async -> Void) {
        isCatchingEdges = false
        Task { @MainActor in
            await completion()
            isCatchingEdges = true
        }
    }

    private func move(to target: Int, fromLeading: Bool) {
        // The countdown starts again once the new banner is in.
        advancing?.cancel()
        isCountingDown = false
        // Drawn now, still covered, so it's there to slide in once the text has gone.
        incomingIndex = target
        incomingHasSlidIn = false
        incomingComesFromLeading = fromLeading
        withAnimation(Metrics.textFadeOut, completionCriteria: .logicallyComplete) {
            showsLabels = false
        } completion: { [self] in
            guard incomingIndex == target else { return }
            // Only once the edge has stopped: swapping the banners before then would uncover the rest
            // of the new one at once.
            withAnimation(Metrics.slide, completionCriteria: .removed) {
                incomingHasSlidIn = true
            } completion: { [self] in
                guard incomingIndex == target else { return }
                index = target
                incomingIndex = nil
                incomingHasSlidIn = false
                warmNextArtwork()
                withAnimation(Metrics.textFadeIn) { showsLabels = true }
                let completions = whenLabelsReturn
                whenLabelsReturn = []
                completions.forEach { $0() }
                restartAdvancing()
            }
        }
    }

    /// Moves on by itself every `interval`, until `stopAdvancing()`.
    func startAdvancing() {
        isAdvancing = true
        restartAdvancing()
    }

    func stopAdvancing() {
        isAdvancing = false
        advancing?.cancel()
        advancing = nil
        isCountingDown = false
    }

    // MARK: Opening the details

    /// Opens the item's full-screen detail view: moves the details and buttons to where a full-screen
    /// card has them, the buttons cross-fading into the card's actions. Focus stays on Info meanwhile.
    /// `then` runs once they're there, to move focus to the actions; `settled` once it has.
    func showDetails(then completion: @escaping () -> Void) {
        guard !detailsAreAway else { return }
        stopAdvancing()
        detailsAreAway = true
        detailsAreMoving = true
        withAnimation(Metrics.details, completionCriteria: .removed) {
            showsDetails = true
        } completion: {
            completion()
        }
    }

    /// Back from the full-screen detail view: moves the details and buttons back, the actions
    /// cross-fading into the buttons. Focus stays on the action it's on meanwhile. `then` runs once
    /// they're back, to move focus to the button it was on last; `settled` once it has.
    func hideDetails(then completion: @escaping () -> Void) {
        guard showsDetails, !detailsAreMoving else { return }
        detailsAreMoving = true
        withAnimation(Metrics.details, completionCriteria: .removed) {
            showsDetails = false
        } completion: {
            completion()
        }
    }

    /// Focus has moved where it belongs after the details moved: the buttons or actions it left stop
    /// taking focus.
    func settled() {
        detailsAreMoving = false
        if !showsDetails { detailsAreAway = false }
    }

    // MARK: Private

    private func restartAdvancing() {
        advancing?.cancel()
        // By itself, it stops at the last banner.
        guard isAdvancing, index < items.count - 1 else {
            isCountingDown = false
            return
        }
        countdown += 1
        isCountingDown = true
        advancing = Task { [weak self, interval] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            self?.next()
        }
    }

    private func setArtworkSizes(of card: MediaCardViewModel) {
        guard let screen else { return }
        card.posterArtworkSize = RemoteImageViewModel.requestSize(for: RelatedMediaGroupPosterView.Metrics.posterSize, scale: screen.scale)
        card.landscapeArtworkSize = RemoteImageViewModel.requestSize(for: screen.size, scale: screen.scale)
        card.logoArtworkSize = RemoteImageViewModel.requestSize(for: MediaCardView.Metrics.detailsLogoSize, scale: screen.scale)
    }

    /// Loads the artwork of the banners either side ahead of time, so it's there to slide in.
    private func warmNextArtwork() {
        for neighbor in [index - 1, index + 1] where items.indices.contains(neighbor) {
            guard let url = card(for: items[neighbor]).landscapeArtworkURL, pipeline.cachedImage(for: url) == nil else { continue }
            Task { [pipeline] in _ = try? await pipeline.image(for: url, priority: .low) }
        }
    }
}

extension HomeBannerViewModel {
    struct Metrics {
        /// The next banner sliding in over the one showing. A curve shaped like `.smooth(duration: 0.6)`,
        /// within 1.5% of it, that stops at its end: a spring is still settling well after it looks
        /// done, and the text waited for it to finish.
        static var slide: Animation { .timingCurve(0.2, 0.15, 0.25, 1, duration: 0.6) }
        /// The text and buttons fading before a banner slides in: slowly enough to see.
        static var textFadeOut: Animation { .easeOut(duration: 0.25) }
        /// And coming back, for the new item, once it has.
        static var textFadeIn: Animation { .easeIn(duration: 0.3) }
        /// The details moving to where the full-screen card has them, and back: as cards move.
        static var details: Animation { RelatedMediaGroupCarouselView.Metrics.layerChange }
    }
}
