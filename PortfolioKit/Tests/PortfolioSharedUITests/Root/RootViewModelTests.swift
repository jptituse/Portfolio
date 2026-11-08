import PortfolioShared
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedUI

struct RootViewModelTests {
    @Test(arguments: [
        (SessionState.restoring, RootViewModel.Destination.launch),
        (.signedOut, .onboarding),
        (.signedIn(.sample()), .main),
    ])
    func showsTheRightViewForEachSessionState(_ state: SessionState, _ destination: RootViewModel.Destination) {
        #expect(RootViewModel.destination(for: state) == destination)
    }
}
