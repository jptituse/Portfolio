import PortfolioShared
import PortfolioSharedJellyfinClient

/// Decides what `RootView` shows, and makes the view models for what it shows. `SessionManager` is
/// observable, so a view reading `destination` updates whenever the session changes.
@MainActor
final class RootViewModel {
    enum Destination: Hashable {
        case launch
        /// Picking a profile, or adding a server.
        case profiles
        case main
    }

    let sessionManager: SessionManager
    private let client: JellyfinServerClient
    private let preferences: DevicePreferences
    /// The open profile's, kept while it stays open: its session changes when it's renamed or its
    /// server moves, which shows the main UI again, and a new one there wouldn't share the preferences
    /// and playback progress the rest of the main UI holds.
    private var currentProfile: (profile: ProfileID, viewModel: CurrentProfileViewModel)?

    init(sessionManager: SessionManager, client: JellyfinServerClient, preferences: DevicePreferences) {
        self.sessionManager = sessionManager
        self.client = client
        self.preferences = preferences
    }

    var destination: Destination {
        Self.destination(for: sessionManager.state)
    }

    nonisolated static func destination(for state: SessionState) -> Destination {
        switch state {
        case .restoring: .launch
        case .choosingProfile: .profiles
        case .signedIn: .main
        }
    }

    /// A fresh start for each time no profile is open: the profile picker, or the welcome screen.
    func makeProfilesViewModel() -> ProfilesViewModel {
        currentProfile = nil
        return ProfilesViewModel(client: client, sessionManager: sessionManager)
    }

    /// The open profile, for the main UI: a fresh one each time a profile opens, so it opens on Home,
    /// and the same one while it stays open.
    func makeCurrentProfileViewModel() -> CurrentProfileViewModel {
        let profile = sessionManager.state.session.map { ProfileID(serverID: $0.server.id, userID: $0.user.id) }
        if let currentProfile, currentProfile.profile == profile {
            return currentProfile.viewModel
        }
        // Kept where the device's are, so UI tests' fresh store holds the profile's too.
        let viewModel = CurrentProfileViewModel(client: client, sessionManager: sessionManager, devicePreferences: preferences, defaults: preferences.defaults)
        currentProfile = profile.map { ($0, viewModel) }
        return viewModel
    }

    /// Loads the saved servers, unless that has already happened, and opens the profile opened last if
    /// Settings says launch skips the profile picker.
    func restoreSession() async {
        guard sessionManager.state == .restoring else { return }
        if preferences.showsProfilePickerOnLaunch {
            sessionManager.restore()
        } else {
            await sessionManager.restoreOpeningLastProfile()
        }
    }
}
