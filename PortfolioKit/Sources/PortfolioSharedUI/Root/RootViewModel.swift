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

    init(sessionManager: SessionManager, client: JellyfinServerClient) {
        self.sessionManager = sessionManager
        self.client = client
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
        ProfilesViewModel(client: client, sessionManager: sessionManager)
    }

    /// The open profile, for the main UI.
    func makeCurrentProfileViewModel() -> CurrentProfileViewModel {
        CurrentProfileViewModel(client: client, sessionManager: sessionManager)
    }

    /// Loads the saved servers, unless that has already happened.
    func restoreSession() {
        if sessionManager.state == .restoring {
            sessionManager.restore()
        }
    }
}
