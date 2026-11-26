import PortfolioShared
import PortfolioSharedJellyfinClient
import SwiftUI

/// The app's top-level view: loads the saved servers at launch, then shows the profiles (picking one,
/// or adding a server) or the main UI of the open profile. Each platform's app supplies its own views
/// for both, made fresh each time, so every profile opens on a fresh main UI.
public struct RootView<Profiles: View, Main: View>: View {
    @State private var viewModel: RootViewModel
    private let profiles: (ProfilesViewModel) -> Profiles
    private let main: (CurrentProfileViewModel) -> Main

    /// - Parameters:
    ///   - profiles: the views for picking a profile or adding a server, given a fresh view model each
    ///     time no profile is open.
    ///   - main: the main UI, given the open profile, to show who it is and switch profiles.
    ///   - preferences: the settings for everyone on this device, such as whether launch opens on the
    ///     profile picker.
    public init(
        sessionManager: SessionManager,
        client: JellyfinServerClient,
        preferences: DevicePreferences,
        @ViewBuilder profiles: @escaping (ProfilesViewModel) -> Profiles,
        @ViewBuilder main: @escaping (CurrentProfileViewModel) -> Main
    ) {
        _viewModel = State(initialValue: RootViewModel(sessionManager: sessionManager, client: client, preferences: preferences))
        self.profiles = profiles
        self.main = main
    }

    public var body: some View {
        SessionRouterView(destination: viewModel.destination) {
            profiles(viewModel.makeProfilesViewModel())
        } main: {
            main(viewModel.makeCurrentProfileViewModel())
        }
        .task { await viewModel.restoreSession() }
    }
}
