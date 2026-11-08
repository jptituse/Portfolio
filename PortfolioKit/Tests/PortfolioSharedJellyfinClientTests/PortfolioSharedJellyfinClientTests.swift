import Testing

@testable import PortfolioSharedJellyfinClient

struct PortfolioSharedJellyfinClientTests {
    @Test func moduleLinks() {
        #expect(PortfolioSharedJellyfinClientModule.name == "PortfolioSharedJellyfinClient")
    }
}
