import CoreGraphics
import PortfolioSharedUI
import Testing

@testable import PortfolioTV

@MainActor
struct MediaItemLayoutTests {
    /// Frames come from floating-point math, so they're compared with a tolerance.
    func approximatelyEqual(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }

    let size = CGSize(width: 1920, height: 1080)
    let posters: [Int: CGRect] = [
        0: CGRect(x: 80, y: 400, width: 250, height: 375),
        1: CGRect(x: 370, y: 400, width: 250, height: 375),
        2: CGRect(x: 660, y: 400, width: 250, height: 375),
    ]

    func layout(current: Int, layer: ViewState = .preview, openCardState: ViewState = .preview) -> MediaItemLayout {
        MediaItemLayout(size: size, itemCount: 3, currentIndex: current, posterFrames: posters, layer: layer, openCardState: openCardState)
    }

    // MARK: Which cards are drawn

    @Test func drawsTheCardsWithPostersInViewAndTheOpenCardsNeighbors() {
        var frames = posters
        frames[3] = CGRect(x: 2000, y: 400, width: 250, height: 375)
        let layout = MediaItemLayout(size: size, itemCount: 10, currentIndex: 8, posterFrames: frames)

        // 0 to 2 are in view, 3 is past the right edge, and 6 to 9 are within two of the open card.
        #expect(layout.drawnIndices == [0, 1, 2, 6, 7, 8, 9])
    }

    // MARK: At the root layer

    @Test func cardsStartOnTheirPosters() {
        let layout = layout(current: 1, layer: .root)
        for (index, frame) in posters {
            #expect(layout.frame(of: index) == frame)
        }
    }

    // MARK: Preview

    @Test func centersTheOpenPlatterAndRunsItToTheBottom() {
        let frame = layout(current: 1).frame(of: 1)
        #expect(approximatelyEqual(frame.midX, size.width / 2))
        #expect(frame.minY == RelatedMediaGroupCarouselView.Metrics.topInset)
        #expect(frame.maxY == size.height)
    }

    @Test func placesNeighborsOnePlatterApart() {
        let layout = layout(current: 1)
        let open = layout.frame(of: 1)
        let next = layout.frame(of: 2)
        let previous = layout.frame(of: 0)
        #expect(approximatelyEqual(next.minX, open.maxX + RelatedMediaGroupCarouselView.Metrics.platterSpacing))
        #expect(approximatelyEqual(previous.maxX, open.minX - RelatedMediaGroupCarouselView.Metrics.platterSpacing))
        // Both neighbors peek in from the edges.
        #expect(previous.maxX > 0)
        #expect(next.minX < size.width)
    }

    // MARK: The previewed card set to the root layer

    @Test func theOpenCardFillsTheCarousel() {
        #expect(layout(current: 1, openCardState: .root).frame(of: 1) == CGRect(origin: .zero, size: size))
    }

    @Test func neighborsArePushedJustOffTheSides() {
        let layout = layout(current: 1, openCardState: .root)
        let previous = layout.frame(of: 0)
        let next = layout.frame(of: 2)
        #expect(approximatelyEqual(previous.maxX, -RelatedMediaGroupCarouselView.Metrics.platterSpacing))
        #expect(approximatelyEqual(next.minX, size.width + RelatedMediaGroupCarouselView.Metrics.platterSpacing))
    }

    // MARK: Artwork

    @Test func aPostersArtworkFillsIt() {
        let layout = layout(current: 1, layer: .root)
        for index in posters.keys {
            #expect(layout.artworkFrame(of: index) == layout.frame(of: index))
        }
    }

    @Test func aPlattersArtworkIsAsBigAsTheScreenAndTheOpenOnesIsCentered() {
        let layout = layout(current: 1)
        #expect(layout.artworkFrame(of: 1) == CGRect(origin: .zero, size: size))
        // The platter shows part of it.
        #expect(layout.artworkFrame(of: 1).contains(layout.frame(of: 1)))
    }

    @Test func neighborsArtworkSitsALittleTowardTheirSide() {
        let layout = layout(current: 1)
        let parallax = RelatedMediaGroupCarouselView.Metrics.artworkParallax
        #expect(layout.artworkFrame(of: 2) == CGRect(origin: CGPoint(x: parallax, y: 0), size: size))
        #expect(layout.artworkFrame(of: 0) == CGRect(origin: CGPoint(x: -parallax, y: 0), size: size))
    }

    @Test func slidingAlongTheRowMovesTheArtworkFarLessThanTheCards() {
        let before = layout(current: 1)
        let after = layout(current: 2)

        let cardMove = before.frame(of: 2).minX - after.frame(of: 2).minX
        let artworkMove = before.artworkFrame(of: 2).minX - after.artworkFrame(of: 2).minX

        // The platter sliding in uncovers its artwork, which comes to the center.
        #expect(artworkMove == RelatedMediaGroupCarouselView.Metrics.artworkParallax)
        #expect(cardMove > artworkMove * 5)
        #expect(after.artworkFrame(of: 2) == CGRect(origin: .zero, size: size))
    }

    @Test func expandingTheOpenCardLeavesItsArtworkWhereItIs() {
        #expect(layout(current: 1, openCardState: .root).artworkFrame(of: 1) == layout(current: 1).artworkFrame(of: 1))
    }

    @Test func expandingPushesTheNeighborsArtworkWithThem() {
        let preview = layout(current: 1)
        let expanded = layout(current: 1, openCardState: .root)
        for index in [0, 2] {
            let cardPush = expanded.frame(of: index).minX - preview.frame(of: index).minX
            let artworkPush = expanded.artworkFrame(of: index).minX - preview.artworkFrame(of: index).minX
            #expect(approximatelyEqual(artworkPush, cardPush))
        }
    }
}

extension MediaItemLayoutTests {
    @Test func theLiftedPosterStartsEnlargedAroundItsCenter() {
        let layout = MediaItemLayout(size: size, itemCount: 3, currentIndex: 1, posterFrames: posters, liftedIndex: 1, layer: .root)
        let lifted = layout.frame(of: 1)
        let resting = posters[1]!

        #expect(approximatelyEqual(lifted.width, resting.width * RelatedMediaGroupCarouselView.Metrics.posterLiftScale))
        #expect(approximatelyEqual(lifted.height, resting.height * RelatedMediaGroupCarouselView.Metrics.posterLiftScale))
        #expect(approximatelyEqual(lifted.midX, resting.midX))
        #expect(approximatelyEqual(lifted.midY, resting.midY))
        // Only the focused poster is lifted.
        #expect(layout.frame(of: 0) == posters[0])
    }
}
