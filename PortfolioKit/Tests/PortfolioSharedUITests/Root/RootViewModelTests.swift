import PortfolioShared
import PortfolioSharedJellyfinClient
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedUI

struct RootViewModelTests {
    @Test(arguments: [
        (SessionState.restoring, RootViewModel.Destination.launch),
        (.choosingProfile, .profiles),
        (.signedIn(.sample()), .main),
    ])
    func showsTheRightViewForEachSessionState(_ state: SessionState, _ destination: RootViewModel.Destination) {
        #expect(RootViewModel.destination(for: state) == destination)
    }

    @MainActor
    @Test func startsTheProfilesAfreshEachTime() {
        let sessionManager = SessionManager(store: MediaServerStore(storage: InMemorySecureStorage()), authority: JellyfinServerClient.mocked)
        let viewModel = RootViewModel(sessionManager: sessionManager, client: .mocked)

        #expect(viewModel.makeProfilesViewModel() !== viewModel.makeProfilesViewModel())
    }

    @MainActor
    @Test func loadsTheMediaServersAtLaunch() {
        let sessionManager = SessionManager(store: MediaServerStore(storage: InMemorySecureStorage()), authority: JellyfinServerClient.mocked)
        let viewModel = RootViewModel(sessionManager: sessionManager, client: .mocked)

        viewModel.restoreSession()

        #expect(viewModel.destination == .profiles)
    }
}
