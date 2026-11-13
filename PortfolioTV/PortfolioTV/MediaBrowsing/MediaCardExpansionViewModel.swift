import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// A card growing from its poster straight to full screen and back, skipping the platter, with nothing
/// else moving: how a grid opens an item. It drives its card the way `MediaBrowsingViewModel` drives a
/// row's. The card's own `viewState` is set to `.root` while it's still a poster, which changes nothing
/// at the `.root` layer. Then the expansion's layer enters `.preview`, which takes the card straight to
/// full screen. Back reverses it, landing on the poster.
///
/// Focus never moves while the card moves: the poster keeps it while the card grows, and the actions
/// take it once the card fills the screen. They keep it while it shrinks back, and the poster gets it
/// again just before the card goes.
@MainActor
@Observable
final class MediaCardExpansionViewModel {
    /// The card that's growing, full screen or shrinking back, if any.
    private(set) var card: MediaCardViewModel?
    /// The expansion's layer: `.root` while the card is on its poster, `.preview` once it fills the
    /// screen. The card inherits it.
    private(set) var layer: ViewState = .root
    /// True while the card starts on its focused poster, which tvOS draws lifted.
    private(set) var startsLifted = false
    /// Whether the full-screen card's actions hold focus, so nothing behind them may take it.
    private(set) var holdsFocus = false

    /// Where each poster is, in global coordinates, so the card can start and end exactly on top of it.
    /// Not observed: posters report their frames as they scroll, which shouldn't redraw anything.
    @ObservationIgnored private var globalPosterFrames: [MediaItem.ID: CGRect] = [:]

    /// The item whose poster the card grew out of.
    var item: MediaItem.ID? { card?.item.id }

    func posterMoved(_ item: MediaItem.ID, to globalFrame: CGRect) {
        globalPosterFrames[item] = globalFrame
    }

    /// A poster was selected: its card goes on top of it, still a poster, ready to grow.
    func select(_ card: MediaCardViewModel) {
        guard self.card == nil else { return }
        // Full screen as far as the card is concerned; the layer entering `.preview` takes it there.
        card.viewState = .root
        layer = .root
        startsLifted = true
        self.card = card
    }

    /// Runs once the card is on screen on top of its poster: grows it to fill the screen. Once it has,
    /// the actions appear and `onGrown` moves focus to them.
    func grow(onGrown: @escaping () -> Void) {
        guard let card, layer == .root else { return }
        withAnimation(MediaCardView.Metrics.labelFadeOut) { card.showsLabels = false }
        withAnimation(RelatedMediaGroupCarouselView.Metrics.layerChange, completionCriteria: .logicallyComplete) {
            layer = .preview
            // From here on the poster frame means the resting one: shrinking back lands on it, and the
            // poster lifts again on its own when it gets focus back.
            startsLifted = false
        } completion: { [self] in
            // Unless Back sent it back meanwhile.
            guard self.card === card, layer == .preview else { return }
            withAnimation(MediaCardView.Metrics.labelFadeIn) {
                holdsFocus = true
                card.showsLabels = true
            }
            onGrown()
        }
    }

    /// Shrinks the card back onto its poster. Once it's there, `onCollapsed` gives the poster focus,
    /// and then the card goes.
    func collapse(onCollapsed: @escaping () -> Void) {
        guard let card, layer == .preview else { return }
        withAnimation(MediaCardView.Metrics.labelFadeOut) { card.showsLabels = false }
        withAnimation(RelatedMediaGroupCarouselView.Metrics.layerChange, completionCriteria: .logicallyComplete) {
            layer = .root
        } completion: { [self] in
            // The poster gets focus before the card goes: removing the card first lets tvOS pick a
            // poster itself.
            holdsFocus = false
            Task { @MainActor in
                onCollapsed()
                self.card = nil
                card.viewState = .preview
                card.showsLabels = true
            }
        }
    }

    /// Where the card is, in the coordinates of a view at `globalFrame` that covers the screen: on its
    /// poster (lifted, as tvOS draws the focused one, while it starts out), or filling the view.
    func frame(in globalFrame: CGRect) -> CGRect {
        guard let item, layer == .root, let globalPoster = globalPosterFrames[item] else {
            return CGRect(origin: .zero, size: globalFrame.size)
        }
        let poster = globalPoster.offsetBy(dx: -globalFrame.minX, dy: -globalFrame.minY)
        guard startsLifted else { return poster }
        typealias Metrics = RelatedMediaGroupCarouselView.Metrics
        // tvOS enlarges a wide poster less, in proportion, than a narrow one.
        let liftScale = poster.width >= RelatedMediaGroupPosterView.Metrics.extendedPosterWidth
            ? Metrics.extendedPosterLiftScale : Metrics.posterLiftScale
        let grow = liftScale - 1
        return poster.insetBy(dx: -poster.width * grow / 2, dy: -poster.height * grow / 2)
    }
}
