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
}
