import CoreGraphics
import PortfolioShared
import PortfolioSharedUI
import Testing

@testable import PortfolioTV

/// Animations finish at once in unit tests, so these see where the banner ends up, not the slide.
@MainActor
struct HomeBannerViewModelTests {
    let items = Array(MediaItem.samples.prefix(3))

    func banner(interval: Duration = .seconds(60)) -> HomeBannerViewModel {
        let banner = HomeBannerViewModel(images: nil, interval: interval)
        banner.setItems(items)
        return banner
    }

    /// Waits for `condition`, for far longer than these tests' short intervals.
    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func startsOnTheFirstItem() {
        let banner = banner()

        #expect(banner.current == items[0])
        #expect(banner.layers == [items[0]])
        #expect(banner.isIdle)
    }

    @Test func movesOnToTheNextItem() {
        let banner = banner()

        banner.next()

        #expect(banner.current == items[1])
        #expect(banner.layers == [items[1]])
        #expect(banner.isIdle)
    }

    @Test func goesRoundFromTheLastToTheFirst() {
        let banner = banner()
        for _ in 0..<items.count - 1 { banner.next() }
        #expect(banner.current == items.last)
        #expect(banner.hasNext)

        banner.next()

        #expect(banner.current == items[0])
        #expect(banner.layers == [items[0]])
    }

    @Test func becomesItsItemsDetailViewAndBack() {
        let banner = banner()
        var areInPlace = false

        banner.showDetails { areInPlace = true }

        #expect(banner.showsDetails)
        #expect(banner.detailsAreAway)
        #expect(areInPlace)
        #expect(!banner.isIdle)
        // Focus is still on Info until it moves to the actions.
        #expect(banner.buttonsTakeFocus)
        #expect(!banner.catchesEdges)

        banner.settled()
        #expect(!banner.buttonsTakeFocus)

        var areBack = false
        banner.hideDetails { areBack = true }

        #expect(!banner.showsDetails)
        #expect(areBack)
        // Focus is still on the actions until it moves to the buttons.
        #expect(banner.detailsAreAway)
        #expect(banner.buttonsTakeFocus)

        banner.settled()
        #expect(!banner.detailsAreAway)
        #expect(banner.catchesEdges)
        #expect(banner.isIdle)
    }

    @Test func stopsMovingOnByItselfWhileItsTheDetailView() {
        let banner = banner()
        banner.startAdvancing()
        #expect(banner.isCountingDown)

        banner.showDetails {}

        #expect(!banner.isCountingDown)
    }

    @Test func goesBackOnlyOnceTheDetailViewHasSettled() {
        let banner = banner()
        banner.showDetails {}
        var areBack = false

        banner.hideDetails { areBack = true }

        #expect(!areBack)
        #expect(banner.showsDetails)
    }

    @Test func staysOnItsItemWhileShowingItsDetails() {
        let banner = banner()
        banner.showDetails {}
        var finished = false

        banner.next { finished = true }

        #expect(banner.current == items[0])
        #expect(finished)
    }

    @Test func remembersTheButtonFocusWasOnLast() {
        let banner = banner()
        #expect(banner.lastButton == .bannerInfo)

        banner.buttonFocused(.bannerNext)

        #expect(banner.lastButton == .bannerNext)
    }

    @Test func goesBackOneAtATimeAndStopsAtTheFirst() {
        let banner = banner()
        banner.next()
        banner.next()

        banner.previous()
        #expect(banner.current == items[1])
        banner.previous()
        banner.previous()

        #expect(banner.current == items[0])
        #expect(!banner.hasPrevious)
    }

    @Test func saysWhenAMoveIsOverOrThereIsNoMoveToMake() {
        let banner = banner()
        var finished = 0

        banner.previous { finished += 1 }
        banner.next { finished += 1 }

        #expect(finished == 2)
        #expect(banner.current == items[1])
    }

    @Test func startsCountingDownOnceItHasSomewhereToGo() {
        let banner = HomeBannerViewModel(images: nil)
        banner.startAdvancing()
        #expect(!banner.isCountingDown)

        banner.setItems(items)

        #expect(banner.isCountingDown)
        banner.stopAdvancing()
        #expect(!banner.isCountingDown)
    }

    @Test func stopsMovingOnByItselfAtTheLast() async throws {
        let banner = banner(interval: .milliseconds(20))

        banner.startAdvancing()
        await waitUntil { banner.current == items.last }
        try await Task.sleep(for: .milliseconds(100))

        #expect(banner.current == items.last)
        #expect(!banner.isCountingDown)
        banner.stopAdvancing()
    }

    @Test func hasNowhereToGoWithOneItem() {
        let banner = HomeBannerViewModel(images: nil)
        banner.setItems([items[0]])

        banner.next()

        #expect(banner.layers == [items[0]])
        #expect(!banner.hasNext)
    }

    @Test func staysOnTheItemItShowsWhenTheItemsChange() {
        let banner = banner()
        let added = MediaItem(id: "new", name: "New", kind: .movie)

        banner.setItems([added] + items)

        #expect(banner.current == items[0])
    }

    @Test func startsOverWhenTheItemItShowsIsGone() {
        let banner = banner()

        banner.setItems(Array(items.dropFirst()))

        #expect(banner.current == items[1])
    }

    @Test func movesOnByItself() async {
        let banner = banner(interval: .milliseconds(50))

        banner.startAdvancing()
        await waitUntil { banner.current == items[1] }

        #expect(banner.current == items[1])
        banner.stopAdvancing()
    }

    @Test func staysPutOnceItStopsMovingOn() async throws {
        let banner = banner(interval: .milliseconds(50))

        banner.startAdvancing()
        banner.stopAdvancing()
        try await Task.sleep(for: .milliseconds(200))

        #expect(banner.current == items[0])
    }

    @Test func fetchesItsArtworkAtTheScreensSize() {
        let banner = banner()
        banner.setScreen(scale: 2, size: CGSize(width: 1920, height: 1080))

        let card = banner.card(for: items[0])

        #expect(card.landscapeArtworkSize == RemoteImageViewModel.requestSize(for: CGSize(width: 1920, height: 1080), scale: 2))
        #expect(card.logoArtworkSize == RemoteImageViewModel.requestSize(for: MediaCardView.Metrics.detailsLogoSize, scale: 2))
        #expect(card === banner.card(for: items[0]))
    }
}
