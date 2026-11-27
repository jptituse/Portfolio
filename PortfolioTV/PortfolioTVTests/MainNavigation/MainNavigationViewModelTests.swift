import PortfolioShared
import PortfolioSharedUI
import SwiftUI
import Testing

@testable import PortfolioTV

@MainActor
struct MainNavigationViewModelTests {
    func viewModel(libraries: [Library] = []) -> MainNavigationViewModel {
        MainNavigationViewModel(libraries: .preview(libraries: libraries))
    }

    @Test func opensOnHomeWithTheSidebarHidden() {
        let viewModel = viewModel()
        // Home, though Search comes first in the sidebar.
        #expect(viewModel.mainSections.first == .search)
        #expect(viewModel.selection == .home)
        #expect(viewModel.columnVisibility == .detailOnly)
    }

    @Test func listsSearchHomeAndSettingsBeforeAnyLibrariesHaveLoaded() {
        let viewModel = viewModel()
        #expect(viewModel.mainSections == [.search, .home])
        #expect(viewModel.otherSections == [.settings])
    }

    @Test func listsTheStandardKindsAboveTheSeparatorAndOtherLibrariesBelowItBeforeSettings() {
        let movies = Library(id: "movies", name: "Movies", kind: .movies)
        let movies4K = Library(id: "4k", name: "4K Movies", kind: .movies)
        let shows = Library(id: "shows", name: "Shows", kind: .tvShows)
        let music = Library(id: "music", name: "Music", kind: .music)

        let viewModel = viewModel(libraries: [movies, music, shows, movies4K])

        #expect(viewModel.mainSections == [.search, .home, .library(.kind(.movies)), .library(.kind(.tvShows))])
        #expect(viewModel.otherSections == [.library(.library(movies)), .library(.library(music)), .library(.library(movies4K)), .settings])
    }

    @Test func keepsOnlyTheSectionsThatHaveBeenOpened() {
        let viewModel = viewModel()
        #expect(viewModel.sectionsToKeep == [.home])

        viewModel.selection = .settings
        #expect(viewModel.sectionsToKeep == [.home, .settings])
    }

    @Test func keepsAnOpenedSectionAfterMovingAway() {
        let viewModel = viewModel()
        viewModel.selection = .search
        viewModel.selection = .home
        #expect(viewModel.sectionsToKeep == [.home, .search])
    }

    // MARK: Item pages

    func page(of card: MediaCardViewModel) -> MediaDetailViewModel {
        MediaDetailViewModel(card: card, loadDetails: { throw CancellationError() })
    }

    @Test func opensThePageBuiltAheadForACardWhereItWasToOpen() {
        let viewModel = viewModel()
        let episode = MediaCardViewModel(item: MediaItem(id: "episode", name: "Episode", kind: .episode))
        var built = 0

        viewModel.prepareDetails(of: episode, opensAt: .card) { built += 1; return page(of: episode) }
        #expect(viewModel.detailPages.map(\.destination) == [.card])
        #expect(viewModel.detailPages.map(\.isRevealed) == [false])

        viewModel.openDetails(of: episode, at: .card, from: .play, making: { built += 1; return page(of: episode) }) { _ in }
        #expect(built == 1)
        #expect(viewModel.detailPages.map(\.isRevealed) == [true])
    }

    @Test func buildsAnEpisodesPageAgainOnceItsClosed() throws {
        let viewModel = viewModel()
        let episode = MediaCardViewModel(item: MediaItem(id: "episode", name: "Episode", kind: .episode))
        viewModel.openDetails(of: episode, at: .card, from: .play, making: { page(of: episode) }) { _ in }
        let closed = try #require(viewModel.detailPages.first?.id)
        viewModel.closeDetails(closed, focusing: .play)

        viewModel.prepareDetails(of: episode, opensAt: .card) { page(of: episode) }
        viewModel.openDetails(of: episode, at: .card, from: .play, making: { page(of: episode) }) { _ in }

        // A page with no card under it goes once it has faded out; the next is built ahead again.
        #expect(viewModel.detailPages.map(\.isRevealed) == [true])
        #expect(viewModel.detailPages.first?.id != closed)
    }

    @Test func letsGoOfAPageBuiltAheadButNotOneShowing() {
        let viewModel = viewModel()
        let show = MediaCardViewModel(item: MediaItem(id: "show", name: "Show", kind: .series))
        let episode = MediaCardViewModel(item: MediaItem(id: "episode", name: "Episode", kind: .episode))
        viewModel.openDetails(of: show, at: .sections, from: .information, making: { page(of: show) }) { _ in }
        viewModel.prepareDetails(of: episode, opensAt: .card) { page(of: episode) }

        viewModel.discardDetails(of: episode)
        viewModel.discardDetails(of: show)

        #expect(viewModel.detailPages.map(\.viewModel.card.item.id) == ["show"])
    }
}
