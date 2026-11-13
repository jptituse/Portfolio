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
}
