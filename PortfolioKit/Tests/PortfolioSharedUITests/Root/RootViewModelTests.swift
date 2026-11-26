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
        let viewModel = RootViewModel(sessionManager: sessionManager, client: .mocked, preferences: DevicePreferences(defaults: .forTesting()))

        #expect(viewModel.makeProfilesViewModel() !== viewModel.makeProfilesViewModel())
    }

    @MainActor
    @Test func loadsTheMediaServersAtLaunch() async {
        let sessionManager = SessionManager(store: MediaServerStore(storage: InMemorySecureStorage()), authority: JellyfinServerClient.mocked)
        let viewModel = RootViewModel(sessionManager: sessionManager, client: .mocked, preferences: DevicePreferences(defaults: .forTesting()))

        await viewModel.restoreSession()

        #expect(viewModel.destination == .profiles)
    }

    @MainActor
    @Test(arguments: [true, false])
    func opensOnTheProfilePickerUnlessSettingsSaysOtherwise(_ showsPicker: Bool) async throws {
        let storage = InMemorySecureStorage()
        try SessionManager(store: MediaServerStore(storage: storage), authority: JellyfinServerClient.mocked).signIn(.sample())
        let relaunched = SessionManager(store: MediaServerStore(storage: storage), authority: JellyfinServerClient.mocked)
        let preferences = DevicePreferences(defaults: .forTesting())
        preferences.showsProfilePickerOnLaunch = showsPicker
        let viewModel = RootViewModel(sessionManager: relaunched, client: .mocked, preferences: preferences)

        await viewModel.restoreSession()

        #expect(viewModel.destination == (showsPicker ? .profiles : .main))
    }
}
