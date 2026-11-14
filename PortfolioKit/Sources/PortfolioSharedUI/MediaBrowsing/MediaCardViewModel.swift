import Foundation
import Observation
import PortfolioShared

/// What a `MediaCardView` shows: its content and the state it's in. The card watches this, so the same
/// card stays on screen while its content and state change.
@MainActor
@Observable
public final class MediaCardViewModel {
    public var item: MediaItem {
        didSet {
            detailInfo.update(with: item)
            detailInfo.logoURL = logoArtworkURL
        }
    }
    /// The card's own layer while its hierarchy is in `.preview`. Setting a previewed card to `.root`
    /// expands it to fill the screen. A card that's `.root` already while its hierarchy enters
    /// `.preview` goes straight from poster to full screen, skipping the platter.
    public var viewState: ViewState = .preview
    /// Whether this is the highlighted card. In a preview, the cards that aren't are darkened.
    public var isFocused = false
    /// Whether a poster has widened to show its landscape thumbnail.
    public var isExtended = false
    /// Whether the labels of the card's current form are showing.
    public var showsLabels = true

    let detailInfo: MediaDetailInfoViewModel
    /// The sizes the artwork is fetched at, in pixels. The poster comes at the size it's drawn in a
    /// row. Landscape art comes at the screen's size, the most a platter's artwork covers, so a wide
    /// poster, its platter and full screen show the very same image, which grows with the card. The
    /// logo comes at the most it takes up on a wide poster.
    public var posterArtworkSize: CGSize?
    public var landscapeArtworkSize: CGSize?
    public var logoArtworkSize: CGSize? {
        didSet { detailInfo.logoURL = logoArtworkURL }
    }
    /// The size the landscape art is fetched at, in pixels, while the card isn't warm, for a card that
    /// shows it at rest: a wide card in a row of them. Without one, it's always fetched at
    /// `landscapeArtworkSize`. Warm cards, which may grow, fetch it at that size, so a row of wide cards
    /// keeps only a few screen-sized images in memory.
    public var restingLandscapeArtworkSize: CGSize?
    /// Whether the landscape art loads ahead of time, so it's ready for the card to fade into as it
    /// moves: for the highlighted card and those beside it.
    public var isWarm = false
    /// Whether the card shows how far along the item is, as in Continue Watching.
    public var showsProgress = false

    @ObservationIgnored private let images: (any MediaImageResolver)?

    /// - Parameter images: where the item's artwork comes from. Without it, the card shows a color.
    public init(item: MediaItem, images: (any MediaImageResolver)? = nil) {
        self.item = item
        self.images = images
        detailInfo = MediaDetailInfoViewModel(item: item)
    }

    /// The title shown on the poster.
    var title: String { item.name }

    /// The poster's shape, width over height: the item's own, so a 16:9 poster is drawn 16:9, else a
    /// movie poster's. Shapes far from any poster's are kept within reason.
    public var posterAspectRatio: CGFloat {
        item.primaryImageAspectRatio.map { min(max(CGFloat($0), Self.aspectRatioRange.lowerBound), Self.aspectRatioRange.upperBound) }
            ?? Self.moviePosterAspectRatio
    }

    /// Where the item's logo is, or nil if it has none, so the title shows instead, or its size isn't
    /// known yet.
    public var logoArtworkURL: URL? {
        logoArtworkSize.flatMap { images?.url(for: item, .logo, pixelSize: $0) }
    }

    /// Where the poster is, or nil if the item has none or its size isn't known yet.
    public var posterArtworkURL: URL? {
        posterArtworkSize.flatMap { images?.url(for: item, .primary, pixelSize: $0) }
    }

    /// Where the landscape art is, or nil if the item has none or its size isn't known yet.
    public var landscapeArtworkURL: URL? {
        let size = (isWarm ? nil : restingLandscapeArtworkSize) ?? landscapeArtworkSize
        return size.flatMap { images?.url(for: item, landscapeArtworkKind, pixelSize: $0) }
    }

    // MARK: Progress

    /// How far into the item the user is, from 0 to 1, or nil if they haven't started it.
    var progress: Double? {
        guard let runtime = item.runtime, runtime > .zero, item.userData.playbackPosition > .zero else { return nil }
        return min(1, item.userData.playbackPosition / runtime)
    }

    /// "S1E5" for an episode, else nil.
    var episodeLabel: String? {
        item.episode?.shortLabel
    }

    /// "23m left", or "1h 12m left", or nil if the item's length isn't known.
    var timeLeftLabel: String? {
        guard let runtime = item.runtime, runtime > .zero else { return nil }
        let left = max(.zero, runtime - item.userData.playbackPosition)
        // Rounded up, so nearly done still reads as a minute left rather than none.
        let minutes = Int((left / .seconds(60)).rounded(.up))
        let formatted = Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        return String(localized: "\(formatted) left")
    }

    /// Whether the progress shows: on a poster in a row that shows it, while the labels are showing.
    func showsProgressIndicator(in layer: ViewState) -> Bool {
        showsProgress && form(in: layer) == .poster && showsLabels
    }

    /// Whether the landscape art covers the poster in a hierarchy at `layer`: once the poster widens,
    /// and on a platter and full screen. Changing this inside the animation that moves the card fades
    /// between them as it moves.
    func showsLandscapeArtwork(in layer: ViewState) -> Bool {
        form(in: layer) != .poster || isExtended
    }

    /// Whether the landscape art is drawn at all: while it shows, or while it's loaded ahead of time.
    /// Otherwise it isn't, so only a few screen-sized images are in memory at once.
    func loadsLandscapeArtwork(in layer: ViewState) -> Bool {
        showsLandscapeArtwork(in: layer) || isWarm
    }

    /// The backdrop, which has no title on it, since the card shows the title itself; else the
    /// thumbnail, else the poster.
    var landscapeArtworkKind: MediaImageKind {
        if item.images[.backdrop()] != nil { return .backdrop() }
        if item.images[.thumb] != nil { return .thumb }
        return .primary
    }

    /// The card's form in a hierarchy at `layer`.
    func form(in layer: ViewState) -> MediaCardForm {
        switch (layer, viewState) {
        case (.root, _): .poster
        case (.preview, .preview): .platter
        case (.preview, .root): .fullScreen
        }
    }

    /// Whether the logo shows: on a poster that has widened, and only while the labels are showing.
    /// A poster at rest shows just its artwork.
    func showsLogo(in layer: ViewState) -> Bool {
        form(in: layer) == .poster && isExtended && showsLabels
    }

    /// Whether the details show: only once the card is bigger than a poster, and only while the labels
    /// are showing.
    func showsDetails(in layer: ViewState) -> Bool {
        form(in: layer).showsDetails && showsLabels
    }

    /// How much the card's actions (Play and the like, drawn above it) show: with its details, as darkened
    /// as the card is on a platter that isn't highlighted.
    public func actionsOpacity(in layer: ViewState) -> Double {
        guard showsDetails(in: layer) else { return 0 }
        return isDimmed(in: layer) ? 1 - MediaCardView.Metrics.dimmedOpacity : 1
    }

    /// Whether the card is darkened: in a preview, the platters that aren't highlighted are.
    func isDimmed(in layer: ViewState) -> Bool {
        form(in: layer) == .platter && !isFocused
    }

    static let moviePosterAspectRatio: CGFloat = 2.0 / 3
    static let aspectRatioRange: ClosedRange<CGFloat> = 0.5...2.4
}
