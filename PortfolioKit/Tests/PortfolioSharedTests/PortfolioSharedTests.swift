import Testing

@testable import PortfolioShared

struct PortfolioSharedTests {
    @Test func moduleLinks() {
        #expect(PortfolioSharedModule.name == "PortfolioShared")
    }
}
