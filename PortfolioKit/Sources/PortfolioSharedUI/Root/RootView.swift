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
    public init(
        sessionManager: SessionManager,
        client: JellyfinServerClient,
        @ViewBuilder profiles: @escaping (ProfilesViewModel) -> Profiles,
        @ViewBuilder main: @escaping (CurrentProfileViewModel) -> Main
    ) {
        _viewModel = State(initialValue: RootViewModel(sessionManager: sessionManager, client: client))
        self.profiles = profiles
        self.main = main
    }

    public var body: some View {
        SessionRouterView(destination: viewModel.destination) {
            profiles(viewModel.makeProfilesViewModel())
        } main: {
            main(viewModel.makeCurrentProfileViewModel())
        }
        // FIXME: The debug sign-out and server removal in Settings still read the session manager from
        // the environment. Pass it to a view model instead once settings (#18) replaces them.
        .environment(viewModel.sessionManager)
        .task { viewModel.restoreSession() }
    }
}
