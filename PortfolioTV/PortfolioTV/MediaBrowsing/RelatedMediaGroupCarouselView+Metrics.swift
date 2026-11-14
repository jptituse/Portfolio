import SwiftUI

extension RelatedMediaGroupCarouselView {
    struct Metrics {
        /// The cards moving between layers: posters, preview and full screen. A curve shaped like
        /// `.smooth(duration: 0.44)`, within 1.5% of it all the way, that stops at its end: a spring is
        /// still settling well after it looks done, and waiting for it to finish before the cards gave
        /// focus back left the screen still for a third of a second.
        static var layerChange: Animation { .timingCurve(0.2, 0.15, 0.25, 1, duration: 0.44) }
        /// The row sliding to another platter.
        static var platterSlide: Animation { .smooth }

        /// Cards drawn beyond the open one on each side, even if their posters are off screen.
        static let neighborsDrawn = 2

        /// How much tvOS enlarges a focused card `width` points wide (its highlight hover effect), around
        /// its center: by `liftShare` of its width, but by no more than `maxLift`. Measured from 4K
        /// frames: a 250-point poster lifts to 554 px wide against 500 at rest, a 480-point card to 1040
        /// against 960, and a 667-point wide poster to 1414 against 1334.
        static func liftScale(forWidth width: CGFloat) -> CGFloat {
            guard width > 0 else { return 1 }
            return 1 + min(width * liftShare, maxLift) / width
        }
        static let liftShare: CGFloat = 0.108
        static let maxLift: CGFloat = 40

        /// Space above the platters; they run to the bottom edge.
        static let topInset: CGFloat = 60
        /// Platter width as a share of the carousel's width; the rest shows the neighbors.
        static let platterWidthShare: CGFloat = 0.88
        static let platterSpacing: CGFloat = 48
        /// How far off center a neighboring platter's artwork sits, toward its side.
        static let artworkParallax: CGFloat = 160
        /// How far open a closing row of wide cards is when their artwork fills them again, and shrinks
        /// with them the rest of the way.
        static let artworkSettling: CGFloat = 0.5
    }
}
