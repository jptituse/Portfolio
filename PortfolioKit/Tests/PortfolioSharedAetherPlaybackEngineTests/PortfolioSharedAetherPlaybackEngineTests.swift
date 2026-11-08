import Testing

@testable import PortfolioSharedAetherPlaybackEngine

struct PortfolioSharedAetherPlaybackEngineTests {
    @Test func moduleLinks() {
        #expect(PortfolioSharedAetherPlaybackEngineModule.name == "PortfolioSharedAetherPlaybackEngine")
    }
}
