import Testing

@testable import PortfolioSharedUI

@MainActor
struct PortfolioSharedUITests {
    @Test func rootViewBuilds() {
        _ = RootView().body
    }
}
