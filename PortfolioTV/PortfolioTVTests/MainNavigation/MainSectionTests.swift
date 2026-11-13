import PortfolioShared
import Testing

@testable import PortfolioTV

@MainActor
struct MainSectionTests {
    @Test func namesEachSection() {
        #expect(MainSection.search.title == "Search")
        #expect(MainSection.home.title == "Home")
        #expect(MainSection.library(.kind(.tvShows)).title == "TV Shows")
        #expect(MainSection.library(.library(Library(id: "4k", name: "4K Movies", kind: .movies))).title == "4K Movies")
        #expect(MainSection.settings.title == "Settings")
    }

    @Test func givesEachSectionAnIcon() {
        for section in [MainSection.search, .home, .library(.kind(.movies)), .settings] {
            #expect(!section.systemImage.isEmpty)
        }
    }
}
