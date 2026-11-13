import SwiftUI

extension RelatedMediaGroupCarouselView {
    struct Metrics {
        /// The cards moving between layers: posters, preview and full screen.
        static var layerChange: Animation { .smooth(duration: 0.44) }
        /// The row sliding to another platter.
        static var platterSlide: Animation { .smooth }

        /// Cards drawn beyond the open one on each side, even if their posters are off screen.
        static let neighborsDrawn = 2

        /// How much tvOS enlarges a focused poster (its highlight hover effect), measured on a
        /// `RelatedMediaGroupPosterView.Metrics.posterSize` poster: 554 px wide when lifted against 500 px at rest,
        /// same center.
        static let posterLiftScale: CGFloat = 1.108
        /// The same for a wide poster: 1414 px wide when lifted against 1334 px at rest.
        static let extendedPosterLiftScale: CGFloat = 1.06

        /// Space above the platters; they run to the bottom edge.
        static let topInset: CGFloat = 60
        /// Platter width as a share of the carousel's width; the rest shows the neighbors.
        static let platterWidthShare: CGFloat = 0.88
        static let platterSpacing: CGFloat = 48
        /// How far off center a neighboring platter's artwork sits, toward its side.
        static let artworkParallax: CGFloat = 160
    }
}
