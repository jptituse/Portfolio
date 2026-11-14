import PortfolioShared
import PortfolioSharedUI
import SwiftUI
import Testing

@testable import PortfolioTV

@MainActor
struct MediaCardExpansionViewModelTests {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let poster = CGRect(x: 500, y: 300, width: 250, height: 375)
    let card = MediaCardViewModel(item: MediaItem(id: "arrival", name: "Arrival", kind: .movie))

    func expansion() -> MediaCardExpansionViewModel {
        let expansion = MediaCardExpansionViewModel()
        expansion.posterMoved("arrival", to: poster)
        return expansion
    }

    @Test func startsOnTheLiftedPosterStillAPoster() {
        let expansion = expansion()

        expansion.select(card)

        #expect(expansion.item == "arrival")
        // Its own layer is full screen already, but the expansion's keeps it a poster for now.
        #expect(card.viewState == .root)
        #expect(expansion.layer == .root)
        let lifted = expansion.frame(in: screen)
        #expect(lifted.midX == poster.midX)
        #expect(lifted.midY == poster.midY)
        #expect(abs(lifted.width - poster.width * RelatedMediaGroupCarouselView.Metrics.liftScale(forWidth: poster.width)) < 0.001)
    }

    @Test func growsStraightToFullScreenSkippingThePlatter() {
        let expansion = expansion()
        expansion.select(card)

        expansion.grow {}

        // The layer entering the preview, with the card's own at `.root`, makes it full screen.
        #expect(expansion.layer == .preview)
        #expect(card.viewState == .root)
        #expect(expansion.frame(in: screen) == CGRect(origin: .zero, size: screen.size))
    }

    @Test func shrinksBackOntoThePosterAtRest() {
        let expansion = expansion()
        expansion.select(card)
        expansion.grow {}

        expansion.collapse {}

        #expect(expansion.layer == .root)
        // The poster lifts again on its own once it has focus back.
        #expect(expansion.frame(in: screen) == poster)
    }

    @Test func measuresThePosterFromWhereItsDrawn() {
        let expansion = expansion()
        expansion.select(card)
        expansion.grow {}
        expansion.collapse {}

        // A view that starts 100 points in sees the poster 100 points nearer.
        #expect(expansion.frame(in: screen.offsetBy(dx: 100, dy: 0)) == poster.offsetBy(dx: -100, dy: 0))
    }

    @Test func expandsOneCardAtATime() {
        let expansion = expansion()
        expansion.select(card)

        expansion.select(MediaCardViewModel(item: MediaItem(id: "dune", name: "Dune", kind: .movie)))

        #expect(expansion.item == "arrival")
    }
}
