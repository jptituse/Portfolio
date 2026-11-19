import Observation
import PortfolioShared
import PortfolioSharedJellyfinClient
import PortfolioSharedPlaybackEngine

/// The open profile, for the main UI to show (on tvOS, at the top of the sidebar). Picking it goes back
/// to the profile picker to switch profiles. It stays signed in, so it opens again from there.
@MainActor
@Observable
public final class CurrentProfileViewModel {
    @ObservationIgnored private let client: JellyfinServerClient
    @ObservationIgnored private let sessionManager: SessionManager
    /// Where items play from, found ahead of Play, by item.
    @ObservationIgnored private var preparedSources: [MediaItem.ID: PreparedSource] = [:]
    /// Where the profile got to in what they've played here, for every card to show.
    public let userDataUpdates = UserDataUpdates()

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
        HomeViewModel(client: client, session: sessionManager.state.session, userDataUpdates: userDataUpdates)
    }

    /// The profile's libraries, loading from their server.
    public func makeLibrariesViewModel() -> LibrariesViewModel {
        LibrariesViewModel(client: client, session: sessionManager.state.session, userDataUpdates: userDataUpdates)
    }

    /// Asks the profile's server where `item` plays from ahead of time, such as once its detail view
    /// opens, so its Play starts sooner. The next player for it uses the answer, within
    /// `preparedSourceLifetime`; asking again meanwhile does nothing.
    public func preparePlayback(of item: MediaItem) {
        guard let session = sessionManager.state.session else { return }
        let now = ContinuousClock.now
        preparedSources = preparedSources.filter { now - $0.value.asked < Self.preparedSourceLifetime }
        guard preparedSources[item.id] == nil else { return }
        let finding = Task { [client] in try await client.playbackSource(for: item, session: session) }
        preparedSources[item.id] = PreparedSource(finding: finding, asked: now)
    }

    /// A player for `item`, played from the profile's server as it is, from the beginning or resuming.
    /// Resuming starts where the server says the user got to when Play is pressed, wherever they
    /// played it, or else where this app last knew. The server hears when it starts, where it is as it
    /// plays and where it stops; a report that fails changes nothing on screen. Once it has stopped,
    /// `userDataUpdates` has the server's word on where the user got to.
    /// Where it plays from was found already if it was prepared; if that failed, it's asked again.
    ///
    /// - Parameter makeEngine: the engine to play it in, of the app's choosing.
    public func makePlayer(for item: MediaItem, from start: PlaybackStart = .beginning, makeEngine: () throws -> any PlaybackEngine) -> PlayerViewModel {
        let session = sessionManager.state.session
        let prepared = takePreparedSource(for: item.id)
        // Asked at once, while where it plays from is found, so resuming doesn't wait for it.
        let resumePosition = start == .resuming ? Task { [client, userDataUpdates] in
            guard let session, let userData = try? await client.userData(for: item, session: session) else {
                return userDataUpdates.userData(for: item).playbackPosition
            }
            return userData.playbackPosition
        } : nil
        return PlayerViewModel(
            title: item.name,
            subtitle: PlayerViewModel.subtitle(for: item),
            makeEngine: makeEngine,
            startingAt: { await resumePosition?.value ?? .zero },
            source: { [client] in
                if let prepared, let found = try? await prepared.value { return found }
                guard let session else { throw JellyfinError.unauthorized }
                return try await client.playbackSource(for: item, session: session)
            },
            describe: { error in
                LoadingFailure.message(for: error, server: session?.server.name ?? "The server", activity: "starting \(item.name)")
            },
            reportStarted: { [client] source, position in
                guard let session else { return }
                try? await client.reportPlaybackStarted(of: item, from: source, at: position, session: session)
            },
            reportProgress: { [client] source, position, isPaused in
                guard let session else { return }
                try? await client.reportPlaybackProgress(of: item, from: source, at: position, isPaused: isPaused, session: session)
            },
            reportStopped: { [client, userDataUpdates] source, position in
                guard let session else { return }
                try? await client.reportPlaybackStopped(of: item, from: source, at: position, session: session)
                // What the server made of it, such as whether it's watched now, for the cards to show.
                if let userData = try? await client.userData(for: item, session: session) {
                    userDataUpdates.update(userData, for: item.id)
                }
            }
        )
    }

    /// The source found ahead of time for an item, if it's still fresh: used once, since each playback
    /// is a play session of its own.
    private func takePreparedSource(for item: MediaItem.ID) -> Task<PlaybackSource, any Error>? {
        guard let prepared = preparedSources.removeValue(forKey: item),
              ContinuousClock.now - prepared.asked < Self.preparedSourceLifetime else { return nil }
        return prepared.finding
    }

    /// How long where an item plays from, found ahead of Play, is used for.
    static let preparedSourceLifetime = Duration.seconds(120)

    private struct PreparedSource {
        let finding: Task<PlaybackSource, any Error>
        let asked: ContinuousClock.Instant
    }
}
