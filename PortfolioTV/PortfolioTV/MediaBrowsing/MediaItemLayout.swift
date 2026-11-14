import CoreGraphics
import PortfolioSharedUI

/// Where each media item of a row sits while the row is open, in the carousel's coordinates.
///
/// Pure geometry. The cards and their artwork are placed from three numbers: how far the row has
/// opened (`progress`), how far the open card has grown to full screen (`expansion`), and where the
/// open card is while the row slides (`openPosition`). Animating those animates every card together.
struct MediaItemLayout {
    /// The carousel's size. It covers the whole browsing view.
    let size: CGSize
    let itemCount: Int
    /// The open card, or the one the row is sliding to.
    let currentIndex: Int
    /// Measured poster frames, by index in the row.
    let posterFrames: [Int: CGRect]
    /// A poster drawn lifted, as tvOS draws the focused one. Its card starts at the lifted size, so
    /// nothing visibly shrinks the moment the row opens.
    var liftedIndex: Int?
    /// How much tvOS enlarges the lifted poster.
    var liftScale: CGFloat
    /// How far the cards have grown from their posters into the preview: 0 on the posters, 1 open.
    var progress: CGFloat
    /// How far the open card has grown from its platter to fill the carousel, pushing its neighbors off
    /// the sides: 0 a platter, 1 full screen.
    var expansion: CGFloat
    /// Where the open card is in the row: `currentIndex` at rest, and between two indices while the row
    /// slides from one platter to the next.
    var openPosition: CGFloat
    /// Whether every poster shows its landscape art, as in a row of wide cards. Otherwise only the open
    /// card's poster may, once it has widened.
    var showsArtworkOnPosters: Bool
    /// Whether the row is closing, going back to its posters, rather than opening.
    var isClosing: Bool

    private typealias Metrics = RelatedMediaGroupCarouselView.Metrics

    /// - Parameters:
    ///   - layer: the layer the row's hierarchy is in. At `.root` the cards sit on their posters.
    ///   - openCardState: the open card's own state. At `.root` it fills the carousel.
    init(
        size: CGSize,
        itemCount: Int,
        currentIndex: Int,
        posterFrames: [Int: CGRect],
        liftedIndex: Int? = nil,
        liftScale: CGFloat = RelatedMediaGroupCarouselView.Metrics.liftScale(forWidth: RelatedMediaGroupPosterView.Metrics.posterSize.width),
        layer: ViewState = .preview,
        openCardState: ViewState = .preview,
        showsArtworkOnPosters: Bool = false
    ) {
        self.size = size
        self.itemCount = itemCount
        self.currentIndex = currentIndex
        self.posterFrames = posterFrames
        self.liftedIndex = liftedIndex
        self.liftScale = liftScale
        progress = layer == .preview ? 1 : 0
        expansion = openCardState == .root ? 1 : 0
        openPosition = CGFloat(currentIndex)
        self.showsArtworkOnPosters = showsArtworkOnPosters
        isClosing = layer == .root
    }

    var platterSize: CGSize {
        CGSize(width: size.width * Metrics.platterWidthShare, height: max(0, size.height - Metrics.topInset))
    }

    /// Leading edge of the centered platter.
    private var centeredX: CGFloat { (size.width - platterSize.width) / 2 }

    /// The cards to draw: those whose posters are in view (they all grow together when the row opens),
    /// plus the open card's nearest neighbors.
    var drawnIndices: [Int] {
        let visible = posterFrames.filter { $0.value.maxX > 0 && $0.value.minX < size.width }.keys
        let lower = max(0, currentIndex - Metrics.neighborsDrawn)
        let upper = min(itemCount - 1, currentIndex + Metrics.neighborsDrawn)
        return Set(visible).union(lower...max(lower, upper)).filter((0..<itemCount).contains).sorted()
    }

    /// Where a card is: its poster moved `progress` of the way to where it is once the row is open.
    func frame(of index: Int) -> CGRect {
        restingFrame(of: index).moved(toward: openFrame(of: index), by: progress)
    }

    func posterFrame(of index: Int) -> CGRect {
        posterFrames[index] ?? CGRect(origin: .zero, size: RelatedMediaGroupPosterView.Metrics.posterSize)
    }

    /// The poster frame enlarged around its center, as tvOS draws a focused poster.
    func liftedPosterFrame(of index: Int) -> CGRect {
        let frame = posterFrame(of: index)
        let grow = liftScale - 1
        return frame.insetBy(dx: -frame.width * grow / 2, dy: -frame.height * grow / 2)
    }

    /// Where a card starts and ends: on its poster, lifted if tvOS draws it so.
    private func restingFrame(of index: Int) -> CGRect {
        index == liftedIndex ? liftedPosterFrame(of: index) : posterFrame(of: index)
    }

    /// Where a card is once the row is open: a platter, or `expansion` of the way to full screen.
    private func openFrame(of index: Int) -> CGRect {
        previewFrame(of: index).moved(toward: expandedFrame(of: index), by: expansion)
    }

    /// The open platter centered, each neighbor one platter width plus spacing further out. Cards
    /// further than the neighbors drawn wait off screen as posters (`waitingFrame(of:)`).
    func previewFrame(of index: Int) -> CGRect {
        if waitsOffScreen(index) { return waitingFrame(of: index) }
        let step = platterSize.width + Metrics.platterSpacing
        let x = centeredX + (CGFloat(index) - openPosition) * step
        return CGRect(origin: CGPoint(x: x, y: Metrics.topInset), size: platterSize)
    }

    /// Whether a card is further from the open one than the neighbors drawn as platters. It stays a
    /// poster, and waits off screen while the row is open.
    func waitsOffScreen(_ index: Int) -> Bool {
        abs(index - currentIndex) > Metrics.neighborsDrawn
    }

    /// Where a card further than the neighbors drawn waits: its poster, pushed along the row as far as
    /// the furthest neighbor's outer edge moves. The rest of the row slides away together, spaced as it
    /// was, without racing across the screen or passing over another card.
    private func waitingFrame(of index: Int) -> CGRect {
        let isAfter = index > currentIndex
        let furthest = currentIndex + (isAfter ? Metrics.neighborsDrawn : -Metrics.neighborsDrawn)
        let platter = previewFrame(of: furthest)
        let poster = posterFrame(of: furthest)
        let push = isAfter ? platter.maxX - poster.maxX : platter.minX - poster.minX
        return posterFrame(of: index).offsetBy(dx: push, dy: 0)
    }

    /// The open card fills the carousel. Its neighbors are pushed out by as much as its edges moved, which
    /// takes them just off the sides.
    func expandedFrame(of index: Int) -> CGRect {
        if index == currentIndex { return CGRect(origin: .zero, size: size) }
        return previewFrame(of: index).offsetBy(dx: push(of: index), dy: 0)
    }

    /// Where a card's artwork is, covering the part of the card on screen. On a platter it's as big as
    /// the carousel, and the card shows the part it covers: the open card's artwork is centered, and
    /// each neighbor's sits a little further toward its own side. Sliding along the row moves the cards a
    /// platter apart but their artwork only that little, so each platter uncovers the artwork beneath it
    /// as it slides in. Expanding the open card uncovers the rest of its artwork, which stays put. A card
    /// waiting off screen stays a poster.
    ///
    /// In a row of wide cards the artwork is what each card shows at rest. Opening, it moves from filling
    /// the card to where a platter's sits all the way, growing with the card. Closing, it goes back to
    /// filling the card early (`artworkSettling`), and then shrinks with it: a neighbor's platter artwork
    /// is centered near the middle of the screen while its card is mostly off it, and moving between the
    /// two all the way, the picture slid one way under its card while the card went the other, so the
    /// cards seemed to bounce. Opening that way instead, the side cards' pictures held still in their
    /// cards and then swung into place.
    func artworkFrame(of index: Int) -> CGRect {
        if waitsOffScreen(index) { return frame(of: index) }
        let card = frame(of: index)
        let open = previewArtworkFrame(of: index).moved(toward: expandedArtworkFrame(of: index), by: expansion)
        let aspectRatio = open.width / max(open.height, 1)
        let artwork = switch (showsArtworkOnPosters, isClosing) {
        case (false, _): posterArtworkFrame(of: index).moved(toward: open, by: progress)
        case (true, false): Self.filling(restingFrame(of: index), aspectRatio: aspectRatio).moved(toward: open, by: progress)
        case (true, true): Self.filling(card, aspectRatio: aspectRatio).moved(toward: open, by: Self.settled(progress))
        }
        return Self.covering(artwork, card: card, visibleWidth: size.width)
    }

    /// How far a wide card's artwork is from filling its card toward where a platter's sits, as its row
    /// closes, at `progress` of the way open: all the way at 1, easing back to none by `artworkSettling`.
    static func settled(_ progress: CGFloat) -> CGFloat {
        let start = Metrics.artworkSettling
        let share = min(max((progress - start) / (1 - start), 0), 1)
        return share * share * (3 - 2 * share)
    }

    /// The smallest frame with `aspectRatio` (width over height) that covers `card`, centered on it.
    static func filling(_ card: CGRect, aspectRatio: CGFloat) -> CGRect {
        let size = card.width / max(card.height, 1) > aspectRatio
            ? CGSize(width: card.width, height: card.width / aspectRatio)
            : CGSize(width: card.height * aspectRatio, height: card.height)
        return CGRect(x: card.midX - size.width / 2, y: card.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// A poster's artwork, in a row of posters. On the open card's poster, which may show it, it fills
    /// the poster. On the others, where it doesn't show yet, it also reaches to the screen's edge on the
    /// side the card moves to, so it covers the part of the card on screen as the card grows without
    /// being moved.
    private func posterArtworkFrame(of index: Int) -> CGRect {
        let poster = restingFrame(of: index)
        guard index != currentIndex else { return poster }
        let minX = index > currentIndex ? poster.minX : min(poster.minX, 0)
        let maxX = index > currentIndex ? max(poster.maxX, size.width) : poster.maxX
        return CGRect(x: minX, y: poster.minY, width: maxX - minX, height: poster.height)
    }

    private func previewArtworkFrame(of index: Int) -> CGRect {
        CGRect(origin: CGPoint(x: (CGFloat(index) - openPosition) * Metrics.artworkParallax, y: 0), size: size)
    }

    private func expandedArtworkFrame(of index: Int) -> CGRect {
        let artwork = previewArtworkFrame(of: index)
        return index == currentIndex ? artwork : artwork.offsetBy(dx: push(of: index), dy: 0)
    }

    /// How far a card's details and actions sit from its leading edge: a platter's way on a platter, and
    /// moving to a full-screen card's as the open card expands, as its details inside it do.
    func detailsLeadingPadding(of index: Int) -> CGFloat {
        let platter = MediaCardView.Metrics.platterDetailsLeadingPadding
        guard index == currentIndex else { return platter }
        return platter + (MediaCardView.Metrics.fullScreenDetailsLeadingPadding - platter) * expansion
    }

    /// How far an expanded card pushes a neighbor: as far as the open card's edge on that side moved.
    private func push(of index: Int) -> CGFloat {
        index < currentIndex ? -centeredX : centeredX
    }

    /// `artwork`, moved (and if it must, enlarged, keeping its shape) as little as it takes to cover the
    /// part of `card` that's on screen, which is `visibleWidth` wide. Midway between a poster and a
    /// platter, a neighbor's card can reach past its artwork; at rest this changes nothing.
    static func covering(_ artwork: CGRect, card: CGRect, visibleWidth: CGFloat) -> CGRect {
        let visibleMinX = max(card.minX, 0)
        let visibleMaxX = min(card.maxX, visibleWidth)
        guard visibleMaxX > visibleMinX, card.height > 0 else { return artwork }
        var frame = artwork
        let scale = max(1, (visibleMaxX - visibleMinX) / max(frame.width, 1), card.height / max(frame.height, 1))
        frame.size = CGSize(width: frame.width * scale, height: frame.height * scale)
        frame.origin.x = min(max(frame.minX, visibleMaxX - frame.width), visibleMinX)
        frame.origin.y = min(max(frame.minY, card.maxY - frame.height), card.minY)
        return frame
    }
}

extension CGRect {
    /// This frame moved `progress` of the way to `target`, as an animation moves it: itself at 0, and
    /// exactly `target` at 1.
    func moved(toward target: CGRect, by progress: CGFloat) -> CGRect {
        if progress == 0 { return self }
        if progress == 1 { return target }
        return CGRect(
            x: minX + (target.minX - minX) * progress,
            y: minY + (target.minY - minY) * progress,
            width: width + (target.width - width) * progress,
            height: height + (target.height - height) * progress
        )
    }
}
