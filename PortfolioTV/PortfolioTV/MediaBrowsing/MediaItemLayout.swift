import CoreGraphics
import PortfolioSharedUI

/// Where each media item of a row sits while the row is open, in the carousel's coordinates.
///
/// Pure geometry, so moving between layers is just animating each card to a new frame.
struct MediaItemLayout {
    /// The carousel's size. It covers the whole browsing view.
    let size: CGSize
    let itemCount: Int
    let currentIndex: Int
    /// Measured poster frames, by index in the row.
    let posterFrames: [Int: CGRect]
    /// A poster drawn lifted, as tvOS draws the focused one. Its card starts at the lifted size, so
    /// nothing visibly shrinks the moment the row opens.
    var liftedIndex: Int?
    /// How much tvOS enlarges the lifted poster.
    var liftScale: CGFloat = RelatedMediaGroupCarouselView.Metrics.posterLiftScale
    /// The layer the row's hierarchy is in. At `.root` the cards sit on their posters.
    var layer: ViewState = .preview
    /// The open card's own state. At `.root` it fills the carousel, pushing its neighbors off the sides.
    var openCardState: ViewState = .preview

    private typealias Metrics = RelatedMediaGroupCarouselView.Metrics

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

    func frame(of index: Int) -> CGRect {
        switch (layer, openCardState) {
        case (.root, _): index == liftedIndex ? liftedPosterFrame(of: index) : posterFrame(of: index)
        case (.preview, .preview): previewFrame(of: index)
        case (.preview, .root): expandedFrame(of: index)
        }
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

    /// The open platter centered, each neighbor one platter width plus spacing further out.
    func previewFrame(of index: Int) -> CGRect {
        let step = platterSize.width + Metrics.platterSpacing
        let x = centeredX + CGFloat(index - currentIndex) * step
        return CGRect(origin: CGPoint(x: x, y: Metrics.topInset), size: platterSize)
    }

    /// The open card fills the carousel. Its neighbors are pushed out by as much as its edges moved, which
    /// takes them just off the sides.
    func expandedFrame(of index: Int) -> CGRect {
        if index == currentIndex { return CGRect(origin: .zero, size: size) }
        let push = index < currentIndex ? -centeredX : centeredX
        return previewFrame(of: index).offsetBy(dx: push, dy: 0)
    }
}
