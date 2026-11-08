import Testing

@testable import PortfolioTV

@MainActor
struct MainSectionTests {
    @Test func listsTheSectionsInSidebarOrder() {
        #expect(MainSection.allCases == [.home, .libraries, .search, .settings])
    }

    @Test func everySectionHasAnIcon() {
        for section in MainSection.allCases {
            #expect(!section.systemImage.isEmpty)
        }
    }
}
