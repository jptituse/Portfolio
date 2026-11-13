import Observation
import PortfolioShared
import PortfolioSharedJellyfinClient

/// The open profile, for the main UI to show (on tvOS, at the top of the sidebar). Picking it goes back
/// to the profile picker to switch profiles. It stays signed in, so it opens again from there.
@MainActor
@Observable
public final class CurrentProfileViewModel {
    @ObservationIgnored private let client: JellyfinServerClient
    @ObservationIgnored private let sessionManager: SessionManager

    init(client: JellyfinServerClient, sessionManager: SessionManager) {
        self.client = client
        self.sessionManager = sessionManager
    }

    /// Who's signed in, with their picture and the server they're on.
    public var tile: ProfileTile? {
        sessionManager.state.session.map { session in
            ProfileTile(
                id: session.user.id,
                name: session.user.name,
                detail: session.server.name,
                pictureURL: client.pictureURL(for: session.user, on: session.server)
            )
        }
    }

    public func switchProfile() {
        sessionManager.closeProfile()
    }

    /// The profile's Home, loading from their server.
    public func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(client: client, session: sessionManager.state.session)
    }

    /// The profile's libraries, loading from their server.
    public func makeLibrariesViewModel() -> LibrariesViewModel {
        LibrariesViewModel(client: client, session: sessionManager.state.session)
    }
}
