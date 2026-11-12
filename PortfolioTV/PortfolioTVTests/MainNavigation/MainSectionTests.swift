import Testing

@testable import PortfolioTV

@MainActor
struct MainSectionTests {
    @Test func listsTheSectionsInSidebarOrder() {
        #expect(MainSection.allCases == [.search, .home, .libraries, .settings])
    }

    @Test func everySectionHasAnIcon() {
        for section in MainSection.allCases {
            #expect(!section.systemImage.isEmpty)
        }
    }
}
