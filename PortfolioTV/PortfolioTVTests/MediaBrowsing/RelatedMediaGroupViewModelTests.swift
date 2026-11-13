import CoreGraphics
import PortfolioShared
import PortfolioSharedUI
import Testing

@testable import PortfolioTV

@MainActor
struct RelatedMediaGroupViewModelTests {
    let group = RelatedMediaGroup(id: "group", title: "Group", items: Array(MediaItem.samples.prefix(3)))
    let carouselFrame = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func makeViewModel(idleDelay: Duration = .seconds(60)) -> RelatedMediaGroupViewModel {
        RelatedMediaGroupViewModel(group: group, idleDelay: idleDelay)
    }

    func card(_ index: Int, in viewModel: RelatedMediaGroupViewModel) -> MediaCardViewModel {
        viewModel.card(for: group.items[index])
    }

    /// Waits for a poster to widen, for far longer than the short delays these tests use.
    func waitUntilExtended(_ card: MediaCardViewModel) async -> Bool {
        for _ in 0..<200 where !card.isExtended {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return card.isExtended
    }

    @Test func usesOneCardPerItem() {
        let viewModel = makeViewModel()
        #expect(card(0, in: viewModel) === card(0, in: viewModel))
        #expect(card(0, in: viewModel) !== card(1, in: viewModel))
    }

    @Test func highlightsOnlyTheFocusedPoster() {
        let viewModel = makeViewModel()
        viewModel.posterFocused(group.items[0].id)
        viewModel.posterFocused(group.items[1].id)

        #expect(viewModel.highlightedItem == group.items[1].id)
        #expect(card(0, in: viewModel).isFocused == false)
        #expect(card(1, in: viewModel).isFocused == true)
    }

    @Test func widensAPosterFocusStaysOn() async {
        let viewModel = makeViewModel(idleDelay: .milliseconds(5))
        viewModel.posterFocused(group.items[0].id)

        #expect(await waitUntilExtended(card(0, in: viewModel)))
        #expect(viewModel.extendedItem == group.items[0].id)
        #expect(viewModel.isMakingRoomToExtend == false)
    }

    @Test func doesNotWidenAPosterFocusMovedOffOf() async {
        let viewModel = makeViewModel(idleDelay: .milliseconds(30))
        viewModel.posterFocused(group.items[0].id)
        viewModel.posterFocused(group.items[1].id)

        #expect(await waitUntilExtended(card(1, in: viewModel)))
        #expect(card(0, in: viewModel).isExtended == false)
    }

    @Test func aWidePosterGoesBackWhenFocusMovesToAnother() async {
        let viewModel = makeViewModel(idleDelay: .milliseconds(5))
        viewModel.posterFocused(group.items[0].id)
        #expect(await waitUntilExtended(card(0, in: viewModel)))

        viewModel.posterFocused(group.items[1].id)
        #expect(card(0, in: viewModel).isExtended == false)
    }

    @Test func aWidePosterGoesBackWhenFocusLeavesTheRow() async {
        let viewModel = makeViewModel(idleDelay: .milliseconds(5))
        viewModel.posterFocused(group.items[0].id)
        #expect(await waitUntilExtended(card(0, in: viewModel)))

        viewModel.focusLeft()
        #expect(card(0, in: viewModel).isExtended == false)
        #expect(card(0, in: viewModel).isFocused == false)
        #expect(viewModel.highlightedItem == nil)
    }

    @Test func openingTheRowStopsAPosterWideningOnItsOwn() async throws {
        let viewModel = makeViewModel(idleDelay: .milliseconds(20))
        viewModel.posterFocused(group.items[0].id)
        viewModel.willOpen(on: group.items[0].id)

        try await Task.sleep(for: .milliseconds(120))
        #expect(card(0, in: viewModel).isExtended == false)
    }

    @Test func theWidePosterFollowsTheHighlightWhileTheRowIsOpen() {
        let viewModel = makeViewModel()
        viewModel.willOpen(on: group.items[0].id)
        viewModel.extendHighlightedPoster()
        viewModel.highlightPlatter(group.items[2].id)

        #expect(card(0, in: viewModel).isExtended == false)
        #expect(card(0, in: viewModel).isFocused == false)
        #expect(card(2, in: viewModel).isExtended == true)
        #expect(card(2, in: viewModel).isFocused == true)
    }

    @Test func aWidePosterStaysWideWhenFocusReturnsToIt() {
        let viewModel = makeViewModel(idleDelay: .milliseconds(5))
        viewModel.willOpen(on: group.items[0].id)
        viewModel.extendHighlightedPoster()
        viewModel.posterFocused(group.items[0].id)

        #expect(card(0, in: viewModel).isExtended == true)
    }
}

// MARK: The open carousel

extension RelatedMediaGroupViewModelTests {
    @Test func measuresPostersFromTheCarouselsCorner() {
        let viewModel = makeViewModel()
        viewModel.posterMoved(group.items[1].id, to: CGRect(x: 400, y: 600, width: 250, height: 375))
        let layout = viewModel.carouselLayout(in: CGRect(x: 100, y: 50, width: 1920, height: 1080), layer: .root)

        #expect(layout.posterFrame(of: 1) == CGRect(x: 300, y: 550, width: 250, height: 375))
    }

    @Test func theOpenCardStartsLiftedLikeItsPoster() {
        typealias Metrics = RelatedMediaGroupCarouselView.Metrics
        let viewModel = makeViewModel()
        viewModel.willOpen(on: group.items[1].id)
        let layout = viewModel.carouselLayout(in: carouselFrame, layer: .root)
        #expect(layout.liftedIndex == 1)
        #expect(layout.liftScale == Metrics.posterLiftScale)

        viewModel.extendHighlightedPoster()
        #expect(viewModel.carouselLayout(in: carouselFrame, layer: .root).liftScale == Metrics.extendedPosterLiftScale)

        viewModel.startsLifted = false
        #expect(viewModel.carouselLayout(in: carouselFrame, layer: .root).liftedIndex == nil)
    }

    @Test func focusComesBackToTheOpenCardOrToItsActionsOnceItHasExpanded() {
        let viewModel = makeViewModel()
        viewModel.willOpen(on: group.items[1].id)
        #expect(viewModel.openCardFocus == .platter(group.items[1].id))

        viewModel.openCard.viewState = .root
        #expect(viewModel.openCardIsExpanded)
        #expect(viewModel.openCardFocus == .detail(group.items[1].id))
    }
    // MARK: Artwork

    @Test func givesEveryCardTheSizesToFetchArtworkAt() {
        let viewModel = makeViewModel()
        let existing = card(0, in: viewModel)

        viewModel.setScreen(scale: 2, size: CGSize(width: 1920, height: 1080))

        // A movie poster as drawn in the row, the whole screen, and the logo in the details, in pixels.
        #expect(existing.posterArtworkSize == CGSize(width: 500, height: 800))
        #expect(existing.landscapeArtworkSize == CGSize(width: 3900, height: 2200))
        #expect(existing.logoArtworkSize == RemoteImageViewModel.requestSize(for: MediaCardView.Metrics.detailsLogoSize, scale: 2))
        // Cards made afterwards get them too.
        #expect(card(2, in: viewModel).landscapeArtworkSize == CGSize(width: 3900, height: 2200))
    }

    @Test func fetchesAWidePosterAtItsOwnShape() {
        let still = MediaItem(id: "still", name: "Pilot", kind: .episode, primaryImageAspectRatio: 16.0 / 9)
        let viewModel = RelatedMediaGroupViewModel(group: RelatedMediaGroup(id: "g", title: "G", items: [still]))
        viewModel.setScreen(scale: 2, size: CGSize(width: 1920, height: 1080))

        #expect(viewModel.card(for: still).posterArtworkSize == CGSize(width: 1400, height: 800))
    }

    // MARK: Poster sizes

    typealias PosterMetrics = RelatedMediaGroupPosterView.Metrics

    func row(of ratios: [Double?]) -> (RelatedMediaGroupViewModel, [MediaItem]) {
        let items = ratios.enumerated().map { MediaItem(id: "item-\($0.offset)", name: "Item", kind: .movie, primaryImageAspectRatio: $0.element) }
        return (RelatedMediaGroupViewModel(group: RelatedMediaGroup(id: "g", title: "G", items: items), idleDelay: .seconds(60)), items)
    }

    @Test func drawsEachPosterInItsOwnShape() {
        let (viewModel, items) = row(of: [nil, 16.0 / 9])

        #expect(viewModel.posterSize(of: viewModel.card(for: items[0])) == PosterMetrics.posterSize)
        #expect(viewModel.posterSize(of: viewModel.card(for: items[1])).width == PosterMetrics.posterSize.height * 16 / 9)
    }

    @Test func widensANarrowPosterToTheWideWidth() {
        let (viewModel, items) = row(of: [nil])
        let card = viewModel.card(for: items[0])

        card.isExtended = true

        #expect(viewModel.posterSize(of: card).width == PosterMetrics.extendedPosterWidth)
    }

    @Test func neverNarrowsAPosterWiderThanTheWideWidth() {
        let (viewModel, items) = row(of: [2.39])
        let card = viewModel.card(for: items[0])
        let resting = viewModel.posterSize(of: card)

        card.isExtended = true

        #expect(viewModel.posterSize(of: card) == resting)
        #expect(resting.width > PosterMetrics.extendedPosterWidth)
    }

    @Test func makesAsMuchRoomAsTheHighlightedPosterGrows() {
        let (viewModel, items) = row(of: [nil, 16.0 / 9])

        viewModel.posterFocused(items[0].id)
        #expect(viewModel.extensionRoom == PosterMetrics.extendedPosterWidth - PosterMetrics.posterSize.width)

        // A 16:9 poster is as wide as it gets already.
        viewModel.posterFocused(items[1].id)
        #expect(viewModel.extensionRoom == 0)
    }

    @Test func warmsTheHighlightedCardAndThoseBesideIt() {
        let group = RelatedMediaGroup(id: "long", title: "Long", items: Array(MediaItem.samples.prefix(8)))
        let viewModel = RelatedMediaGroupViewModel(group: group, idleDelay: .seconds(60))

        viewModel.posterFocused(group.items[4].id)

        let warm = group.items.filter { viewModel.card(for: $0).isWarm }.map(\.id)
        let reach = RelatedMediaGroupCarouselView.Metrics.neighborsDrawn
        #expect(warm == group.items[(4 - reach)...(4 + reach)].map(\.id))
    }

    @Test func coolsTheCardsFocusLeaves() {
        let viewModel = makeViewModel()
        viewModel.posterFocused(group.items[0].id)

        viewModel.focusLeft()

        #expect(group.items.allSatisfy { !viewModel.card(for: $0).isWarm })
    }

    @Test func warmsAroundThePlatterTheRowSlidesTo() {
        let group = RelatedMediaGroup(id: "long", title: "Long", items: Array(MediaItem.samples.prefix(8)))
        let viewModel = RelatedMediaGroupViewModel(group: group, idleDelay: .seconds(60))
        viewModel.posterFocused(group.items[0].id)

        viewModel.highlightPlatter(group.items[5].id)

        #expect(!viewModel.card(for: group.items[0]).isWarm)
        #expect(viewModel.card(for: group.items[7]).isWarm)
    }
}
