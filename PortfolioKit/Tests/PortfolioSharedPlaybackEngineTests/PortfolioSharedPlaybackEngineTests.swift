import Testing

@testable import PortfolioSharedPlaybackEngine

struct PortfolioSharedPlaybackEngineTests {
    @Test func moduleLinks() {
        #expect(PortfolioSharedPlaybackEngineModule.name == "PortfolioSharedPlaybackEngine")
    }
}
