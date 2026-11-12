import SwiftUI
import Testing

@testable import PortfolioTV

@MainActor
struct MainNavigationViewModelTests {
    @Test func opensOnHomeWithTheSidebarHidden() {
        let viewModel = MainNavigationViewModel()
        // Home, though Search comes first in the sidebar.
        #expect(MainSection.allCases.first != .home)
        #expect(viewModel.selection == .home)
        #expect(viewModel.columnVisibility == .detailOnly)
    }

    @Test func keepsOnlyTheSectionsThatHaveBeenOpened() {
        let viewModel = MainNavigationViewModel()
        #expect(viewModel.sectionsToKeep == [.home])

        viewModel.selection = .settings
        #expect(viewModel.sectionsToKeep == [.home, .settings])
    }

    @Test func keepsAnOpenedSectionAfterMovingAway() {
        let viewModel = MainNavigationViewModel()
        viewModel.selection = .search
        viewModel.selection = .home
        #expect(viewModel.sectionsToKeep == [.search, .home])
    }
}
