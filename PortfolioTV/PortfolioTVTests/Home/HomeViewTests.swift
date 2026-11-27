import Testing

@testable import PortfolioTV

@MainActor
struct HomeViewTests {
    @Test(arguments: [HomeFocus.bannerPlay, .bannerInfo, .bannerNext, .bannerLeftEdge, .bannerRightEdge])
    func countsTheBannersButtonsAndWhatCatchesFocusBesideThemAsTheBanner(_ focus: HomeFocus) {
        #expect(HomeView.isInBanner(focus))
    }

    @Test func doesntCountNothingAsTheBanner() {
        #expect(!HomeView.isInBanner(nil))
    }
}
