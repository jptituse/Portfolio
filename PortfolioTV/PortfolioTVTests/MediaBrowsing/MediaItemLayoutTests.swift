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

    @Test func theOpenPostersArtworkFillsIt() {
        let layout = layout(current: 1, layer: .root)
        #expect(layout.artworkFrame(of: 1) == layout.frame(of: 1))
    }

    @Test func everyCardsArtworkFillsItInARowOfWideCards() {
        let layout = longLayout(current: 1, layer: .root, wideCards: true)
        for index in layout.drawnIndices {
            let (artwork, card) = (layout.artworkFrame(of: index), layout.frame(of: index))
            #expect([artwork.minX - card.minX, artwork.minY - card.minY, artwork.width - card.width, artwork.height - card.height].allSatisfy { abs($0) < 0.001 }, "Card \(index): \(artwork) on \(card)")
        }
    }

    @Test func openingMovesAWideCardsArtworkTowardAPlattersAllTheWay() {
        var layout = longLayout(current: 4, wideCards: true)
        for index in [3, 4, 5] {
            layout.progress = 0
            let start = layout.artworkFrame(of: index)
            layout.progress = 1
            let end = layout.artworkFrame(of: index)
            layout.progress = 0.25
            let quarter = layout.artworkFrame(of: index)

            // A quarter of the way, enlarged only if it must be to cover its card.
            let expected = MediaItemLayout.covering(start.moved(toward: end, by: 0.25), card: layout.frame(of: index), visibleWidth: size.width)
            #expect(approximatelyEqual(quarter.minX, expected.minX) && approximatelyEqual(quarter.width, expected.width), "Card \(index)")
        }
    }

    @Test func closingFitsAWideCardsArtworkToItEarly() {
        var layout = longLayout(current: 4, layer: .root, wideCards: true)
        for progress in Self.progressSteps where progress <= RelatedMediaGroupCarouselView.Metrics.artworkSettling {
            layout.progress = progress
            for index in layout.drawnIndices where !layout.waitsOffScreen(index) {
                let card = layout.frame(of: index)
                let artwork = layout.artworkFrame(of: index)
                // Centered on its card and just covering it, so it grows and shrinks with it.
                #expect(approximatelyEqual(artwork.midX, card.midX) && approximatelyEqual(artwork.midY, card.midY), "Card \(index) at \(progress)")
                #expect(approximatelyEqual(artwork.width, card.width) || approximatelyEqual(artwork.height, card.height), "Card \(index) at \(progress)")
            }
        }
    }

    @Test func aWideCardsArtworkEndsWhereAPlattersSits() {
        let open = longLayout(current: 4, wideCards: true)
        let posters = longLayout(current: 4)
        for index in [2, 3, 4, 5, 6] {
            #expect(open.artworkFrame(of: index) == posters.artworkFrame(of: index))
        }
    }

    @Test func aNeighborsArtworkReachesTheScreensEdgeOnItsSideWhileItsAPoster() {
        let layout = layout(current: 1, layer: .root)
        let next = layout.artworkFrame(of: 2)
        let previous = layout.artworkFrame(of: 0)

        #expect(next == CGRect(x: posters[2]!.minX, y: posters[2]!.minY, width: size.width - posters[2]!.minX, height: posters[2]!.height))
        #expect(previous == CGRect(x: 0, y: posters[0]!.minY, width: posters[0]!.maxX, height: posters[0]!.height))
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

    @Test func theOpenCardsActionsMoveToAFullScreenCardsPlaceAsItExpands() {
        var layout = layout(current: 1)
        let platter = MediaCardView.Metrics.platterDetailsLeadingPadding
        let fullScreen = MediaCardView.Metrics.fullScreenDetailsLeadingPadding
        #expect(layout.detailsLeadingPadding(of: 1) == platter)

        layout.expansion = 0.5
        #expect(approximatelyEqual(layout.detailsLeadingPadding(of: 1), (platter + fullScreen) / 2))
        // A neighbor's stay a platter's.
        #expect(layout.detailsLeadingPadding(of: 2) == platter)

        layout.expansion = 1
        #expect(layout.detailsLeadingPadding(of: 1) == fullScreen)
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

// MARK: A long row moving

extension MediaItemLayoutTests {
    /// Ten posters in a row, the last few past the screen's right edge.
    var longRow: [Int: CGRect] {
        Dictionary(uniqueKeysWithValues: (0..<10).map { ($0, CGRect(x: 80 + CGFloat($0) * 290, y: 400, width: 250, height: 375)) })
    }

    /// Ten wide cards in a row, as in Continue Watching, the last few past the screen's right edge.
    var wideRow: [Int: CGRect] {
        Dictionary(uniqueKeysWithValues: (0..<10).map { ($0, CGRect(x: 80 + CGFloat($0) * 520, y: 400, width: 480, height: 270)) })
    }

    func longLayout(current: Int, layer: ViewState = .preview, wideCards: Bool = false) -> MediaItemLayout {
        MediaItemLayout(
            size: size,
            itemCount: 10,
            currentIndex: current,
            posterFrames: wideCards ? wideRow : longRow,
            liftedIndex: current,
            layer: layer,
            showsArtworkOnPosters: wideCards
        )
    }

    /// The points of a motion checked, from start to end.
    static let progressSteps = stride(from: 0.0, through: 1.0, by: 0.05).map { CGFloat($0) }

    func expectNoOverlap(_ layout: MediaItemLayout, _ comment: String) {
        let frames = layout.drawnIndices.map(layout.frame(of:))
        for (a, first) in frames.enumerated() {
            for second in frames[(a + 1)...] {
                #expect(first.intersection(second).width < 0.001, "Overlap \(comment)")
            }
        }
    }

    func expectArtworkCoversCards(_ layout: MediaItemLayout, _ comment: String) {
        let screen = CGRect(origin: .zero, size: size)
        for index in layout.drawnIndices {
            let onScreen = layout.frame(of: index).intersection(screen)
            guard !onScreen.isNull, onScreen.width > 0 else { continue }
            #expect(layout.artworkFrame(of: index).insetBy(dx: -0.001, dy: -0.001).contains(onScreen), "Card \(index) uncovered \(comment)")
        }
    }

    @Test func cardsFurtherOutWaitOffScreenAsPostersSpacedAsInTheRow() {
        let layout = longLayout(current: 1)
        let waiting = (4..<10).map { layout.frame(of: $0) }

        #expect((4..<10).allSatisfy(layout.waitsOffScreen))
        #expect(!layout.waitsOffScreen(3))
        #expect(waiting.allSatisfy { $0.size == longRow[0]!.size && $0.minX > size.width })
        // As far from the furthest platter, and from each other, as their posters are in the row.
        let gap = longRow[4]!.minX - longRow[3]!.maxX
        #expect(approximatelyEqual(waiting[0].minX - layout.frame(of: 3).maxX, gap))
        #expect(approximatelyEqual(waiting[1].minX - waiting[0].maxX, gap))
    }

    @Test func partwayACardIsThatFarFromItsPosterToItsPlatter() {
        var layout = longLayout(current: 1)
        let platter = layout.frame(of: 2)
        layout.progress = 0
        let poster = layout.frame(of: 2)

        layout.progress = 0.25

        #expect(layout.frame(of: 2) == poster.moved(toward: platter, by: 0.25))
    }

    @Test(arguments: [0, 1, 4])
    func noTwoCardsOverlapAsTheRowOpensOrCloses(current: Int) {
        var layout = longLayout(current: current)
        for progress in Self.progressSteps {
            layout.progress = progress
            expectNoOverlap(layout, "at \(progress)")
        }
    }

    @Test(arguments: [(0, false), (1, false), (4, false), (1, true), (4, true)], [ViewState.preview, .root])
    func theArtworkCoversTheCardOnScreenAllTheWayAsTheRowOpensOrCloses(row: (current: Int, wideCards: Bool), toward layer: ViewState) {
        var layout = longLayout(current: row.current, layer: layer, wideCards: row.wideCards)
        for progress in Self.progressSteps {
            layout.progress = progress
            expectArtworkCoversCards(layout, "at \(progress)")
        }
    }

    @Test func theArtworkCoversTheCardsAllTheWayAsTheOpenOneExpands() {
        var layout = longLayout(current: 4)
        for expansion in Self.progressSteps {
            layout.expansion = expansion
            expectArtworkCoversCards(layout, "at \(expansion)")
        }
    }

    @Test func slidingMovesThePlattersAndTheirArtworkSmoothlyToTheNextOne() {
        var layout = longLayout(current: 5)
        let settled = layout.frame(of: 5)
        layout.openPosition = 4.5

        // Halfway from the platter before.
        let step = layout.platterSize.width + RelatedMediaGroupCarouselView.Metrics.platterSpacing
        #expect(approximatelyEqual(layout.frame(of: 5).minX, settled.minX + step / 2))
        expectNoOverlap(layout, "while sliding")
        expectArtworkCoversCards(layout, "while sliding")
    }

    @Test func theLiftedPosterStartsEnlargedAroundItsCenter() {
        let layout = MediaItemLayout(size: size, itemCount: 3, currentIndex: 1, posterFrames: posters, liftedIndex: 1, layer: .root)
        let lifted = layout.frame(of: 1)
        let resting = posters[1]!

        let scale = RelatedMediaGroupCarouselView.Metrics.liftScale(forWidth: resting.width)
        #expect(approximatelyEqual(lifted.width, resting.width * scale))
        #expect(approximatelyEqual(lifted.height, resting.height * scale))
        #expect(approximatelyEqual(lifted.midX, resting.midX))
        #expect(approximatelyEqual(lifted.midY, resting.midY))
        // Only the focused poster is lifted.
        #expect(layout.frame(of: 0) == posters[0])
    }
}
