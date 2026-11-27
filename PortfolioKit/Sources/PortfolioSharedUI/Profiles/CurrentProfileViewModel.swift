import Foundation
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
    @ObservationIgnored private let devicePreferences: DevicePreferences
    /// Where items play from, found ahead of Play, by item.
    @ObservationIgnored private var preparedSources: [MediaItem.ID: PreparedSource] = [:]
    /// Each item's details, asked once a full-screen card or page shows them, kept while the profile is
    /// open. A failed ask is forgotten, so the next asks again.
    @ObservationIgnored private var details: [MediaItem.ID: Task<MediaItemDetails, any Error>] = [:]
    /// Items like each item, asked along with its details, so its page opens with them.
    @ObservationIgnored private var similarItems: [MediaItem.ID: Task<[MediaItem], any Error>] = [:]
    /// Each show's episodes, by show, asked along with a show's or an episode's details.
    @ObservationIgnored private var episodes: [String: Task<[MediaItem], any Error>] = [:]
    /// The answers so far, so a page opens on them rather than waiting a moment for the asks to end.
    @ObservationIgnored private var knownDetails: [MediaItem.ID: MediaItemDetails] = [:]
    @ObservationIgnored private var knownSimilarItems: [MediaItem.ID: [MediaItem]] = [:]
    @ObservationIgnored private var knownEpisodes: [String: [MediaItem]] = [:]
    /// Each show's episodes as the server has them, asked ahead of Play on the show, by show.
    @ObservationIgnored private var preparedEpisodes: [String: PreparedEpisodes] = [:]
    /// The cards of shows whose details were asked for, by show, to show their next episode again
    /// once one has played.
    @ObservationIgnored private var showCards: [String: NSHashTable<MediaCardViewModel>] = [:]
    /// Where the profile got to in what they've played here, for every card to show.
    public let userDataUpdates = UserDataUpdates()
    /// The profile's own settings.
    public let preferences: ProfilePreferences?

    init(client: JellyfinServerClient, sessionManager: SessionManager, devicePreferences: DevicePreferences, defaults: UserDefaults = .standard) {
        self.client = client
        self.sessionManager = sessionManager
        self.devicePreferences = devicePreferences
        preferences = sessionManager.state.session.map { session in
            ProfilePreferences(profile: ProfileID(serverID: session.server.id, userID: session.user.id), defaults: defaults)
        }
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
        HomeViewModel(client: client, session: sessionManager.state.session, userDataUpdates: userDataUpdates, preferences: preferences)
    }

    /// Settings, for this device and this profile.
    ///
    /// - Parameter engine: the playback engine's name and version, for About.
    public func makeSettingsViewModel(engine: (name: String, version: String)) -> SettingsViewModel {
        SettingsViewModel(
            devicePreferences: devicePreferences,
            profilePreferences: preferences,
            sessionManager: sessionManager,
            client: client,
            engine: engine
        )
    }

    /// Search, of the profile's server.
    public func makeSearchViewModel() -> SearchViewModel {
        SearchViewModel(client: client, session: sessionManager.state.session, userDataUpdates: userDataUpdates)
    }

    /// The profile's libraries, loading from their server.
    public func makeLibrariesViewModel() -> LibrariesViewModel {
        LibrariesViewModel(client: client, session: sessionManager.state.session, userDataUpdates: userDataUpdates)
    }

    /// Asks the profile's server for what `card`'s item's page shows beyond the card, once its full-screen
    /// actions are in use, so the card shows its format badges and credits, and its page opens on them.
    public func prepareDetails(for card: MediaCardViewModel) {
        Task { [weak self] in _ = try? await self?.similarItems(to: card.item) }
        if let show = MediaDetailViewModel.showID(of: card.item) {
            // A show's card describes its next episode, which Play plays.
            if card.item.kind == .series {
                let cards = showCards[show] ?? .weakObjects()
                cards.add(card)
                showCards[show] = cards
            }
            Task { [weak self] in
                guard let episodes = try? await self?.episodes(ofShow: show) else { return }
                self?.showNextEpisode(on: card, of: episodes)
            }
        }
        Task { [weak self] in
            guard let found = try? await self?.details(of: card.item) else { return }
            card.detailInfo.update(with: found)
        }
    }

    /// The page of `card`'s item, below its full-screen card, from the profile's server.
    ///
    /// - Parameter listsEpisodes: whether a show's or an episode's page lists the show's episodes: not
    ///   an episode's own, opened from that list, which goes straight on to its cast.
    public func makeDetail(for card: MediaCardViewModel, listsEpisodes: Bool = true) -> MediaDetailViewModel {
        let session = sessionManager.state.session
        let item = card.item
        let show = listsEpisodes ? MediaDetailViewModel.showID(of: item) : nil
        var loadEpisodes: (@MainActor () async throws -> [MediaItem])?
        if let show {
            loadEpisodes = { [weak self] in
                guard let self else { throw CancellationError() }
                return try await episodes(ofShow: show)
            }
        }
        return MediaDetailViewModel(
            card: card,
            loadDetails: { [weak self] in
                guard let self else { throw CancellationError() }
                return try await details(of: item)
            },
            loadSimilar: { [weak self] in
                guard let self else { throw CancellationError() }
                return try await similarItems(to: item)
            },
            loadEpisodes: loadEpisodes,
            images: session.map { JellyfinImageResolver(server: $0.server) },
            userDataUpdates: userDataUpdates,
            details: knownDetails[item.id],
            similar: knownSimilarItems[item.id],
            episodes: show.flatMap { knownEpisodes[$0] }
        )
    }

    /// Describes the next of a show's `episodes` on its `card`, with what's been played here since.
    private func showNextEpisode(on card: MediaCardViewModel, of episodes: [MediaItem]) {
        guard card.item.kind == .series,
              let next = MediaDetailViewModel.startingEpisode(of: card.item, in: episodes, userData: userDataUpdates.userData(for:)) else { return }
        card.detailInfo.update(nextEpisode: next, isWatched: userDataUpdates.userData(for: next).isPlayed)
    }

    /// Once an episode of `show` has played, its show's cards describe the next one.
    private func showNextEpisodes(ofShow show: String) {
        guard let episodes = knownEpisodes[show] else { return }
        for card in showCards[show]?.allObjects ?? [] {
            showNextEpisode(on: card, of: episodes)
        }
    }

    /// The show `seriesID`'s episodes from the profile's server, asked once and shared.
    private func episodes(ofShow seriesID: String) async throws -> [MediaItem] {
        if let asked = episodes[seriesID] {
            return try await asked.value
        }
        guard let session = sessionManager.state.session else { throw JellyfinError.unauthorized }
        let asking = Task { [client] in try await client.episodes(ofShow: seriesID, session: session) }
        episodes[seriesID] = asking
        do {
            let found = try await asking.value
            knownEpisodes[seriesID] = found
            return found
        } catch {
            if episodes[seriesID] == asking { episodes[seriesID] = nil }
            throw error
        }
    }

    /// Items like `item` from the profile's server, asked once and shared.
    private func similarItems(to item: MediaItem) async throws -> [MediaItem] {
        if let asked = similarItems[item.id] {
            return try await asked.value
        }
        guard let session = sessionManager.state.session else { throw JellyfinError.unauthorized }
        let asking = Task { [client] in try await client.similarItems(to: item, session: session) }
        similarItems[item.id] = asking
        do {
            let found = try await asking.value
            knownSimilarItems[item.id] = found
            return found
        } catch {
            if similarItems[item.id] == asking { similarItems[item.id] = nil }
            throw error
        }
    }

    /// `item`'s details from the profile's server, asked once and shared.
    private func details(of item: MediaItem) async throws -> MediaItemDetails {
        if let asked = details[item.id] {
            return try await asked.value
        }
        guard let session = sessionManager.state.session else { throw JellyfinError.unauthorized }
        let asking = Task { [client] in try await client.details(of: item, session: session) }
        details[item.id] = asking
        do {
            let found = try await asking.value
            knownDetails[item.id] = found
            return found
        } catch {
            if details[item.id] == asking { details[item.id] = nil }
            throw error
        }
    }

    /// Asks the profile's server where `item` plays from ahead of time, such as once its detail view
    /// opens, so its Play starts sooner. The next player for it uses the answer, within
    /// `preparedSourceLifetime`; asking again meanwhile does nothing.
    public func preparePlayback(of item: MediaItem) {
        // A show plays its next episode, found first.
        if item.kind == .series {
            Task { [weak self] in
                guard let self, let (episode, _) = await nextEpisode(ofShow: item, takingPrepared: false) else { return }
                preparePlayback(of: episode)
            }
            return
        }
        guard let session = sessionManager.state.session else { return }
        let now = ContinuousClock.now
        preparedSources = preparedSources.filter { now - $0.value.asked < Self.preparedSourceLifetime }
        guard preparedSources[item.id] == nil else { return }
        let request = PlaybackDefaults(preferences, item: item).startingRequest
        let finding = Task { [client] in try await client.playbackSource(for: item, request, session: session) }
        preparedSources[item.id] = PreparedSource(finding: finding, asked: now)
    }

    /// The episode Play on `show` plays, and where from: where the user is in it, as its page's row of
    /// episodes starts (`MediaDetailViewModel.startingEpisode(of:in:userData:)`), resuming it if
    /// they're partway through. The show's episodes are asked of the server as Play is pressed, so it
    /// goes by where the user got to wherever they played it, with what they've played here since; asked
    /// ahead (`preparePlayback(of:)`), that answer is used once, within 2 minutes. Nil if the show has no
    /// episodes, or the server couldn't say and none are known.
    public func nextEpisode(ofShow show: MediaItem) async -> (episode: MediaItem, start: PlaybackStart)? {
        await nextEpisode(ofShow: show, takingPrepared: true)
    }

    private func nextEpisode(ofShow show: MediaItem, takingPrepared: Bool) async -> (episode: MediaItem, start: PlaybackStart)? {
        let now = ContinuousClock.now
        preparedEpisodes = preparedEpisodes.filter { now - $0.value.asked < Self.preparedSourceLifetime }
        let prepared = preparedEpisodes[show.id] ?? PreparedEpisodes(finding: Task { [weak self] in
            guard let self, let session = sessionManager.state.session else { return nil }
            return try? await client.episodes(ofShow: show.id, session: session)
        }, asked: now)
        preparedEpisodes[show.id] = takingPrepared ? nil : prepared
        var episodes = await prepared.finding.value
        if episodes == nil { episodes = knownEpisodes[show.id] }
        guard let episodes else { return nil }
        let next = MediaDetailViewModel.startingEpisode(of: show, in: episodes) { [userDataUpdates] in userDataUpdates.userData(for: $0) }
        return next.map { ($0, userDataUpdates.userData(for: $0).canResume ? .resuming : .beginning) }
    }

    /// A player for `item`, played from the profile's server, from the beginning or resuming: as it is
    /// wherever the server will send it so, else as a stream the server makes, and as one for any choice
    /// of tracks or quality that needs it, the server stopping each stream the player moves on from.
    /// Resuming starts where the server says the user got to when Play is pressed, wherever they
    /// played it, or else where this app last knew. The server hears when it starts, where it is as it
    /// plays and where it stops; a report that fails changes nothing on screen. Once it has stopped,
    /// `userDataUpdates` has the server's word on where the user got to.
    /// Where it plays from was found already if it was prepared; if that failed, it's asked again.
    /// Auto streams no faster than the profile's Settings say, and it starts in their audio and subtitle
    /// languages, on Style's Original if the item, or its show, played last with it, which it keeps for
    /// the item, or for the whole show (`PlaybackDefaults`).
    ///
    /// - Parameter makeEngine: the engine to play it in, of the app's choosing.
    public func makePlayer(for item: MediaItem, from start: PlaybackStart = .beginning, makeEngine: () throws -> any PlaybackEngine) -> PlayerViewModel {
        let session = sessionManager.state.session
        let prepared = takePreparedSource(for: item.id)
        let defaults = PlaybackDefaults(preferences, item: item)
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
            source: { [client] request in
                // Prepared as a player starts.
                if request == defaults.startingRequest, let prepared, let found = try? await prepared.value { return found }
                guard let session else { throw JellyfinError.unauthorized }
                return try await client.playbackSource(for: item, request, session: session)
            },
            describe: { error in
                LoadingFailure.message(for: error, server: session?.server.name ?? "The server", activity: "starting \(item.name)")
            },
            stopTranscoding: { [client] source in
                guard let session else { return }
                try? await client.stopTranscoding(source, session: session)
            },
            reportStarted: { [client] source, position in
                guard let session else { return }
                try? await client.reportPlaybackStarted(of: item, from: source, at: position, session: session)
            },
            reportProgress: { [client] source, position, isPaused in
                guard let session else { return }
                try? await client.reportPlaybackProgress(of: item, from: source, at: position, isPaused: isPaused, session: session)
            },
            reportStopped: { [weak self, client, userDataUpdates] source, position in
                guard let session else { return }
                try? await client.reportPlaybackStopped(of: item, from: source, at: position, session: session)
                // What the server made of it, such as whether it's watched now, for the cards to show.
                if let userData = try? await client.userData(for: item, session: session) {
                    userDataUpdates.update(userData, for: item.id)
                    if let show = item.episode?.seriesID { self?.showNextEpisodes(ofShow: show) }
                }
            },
            playbackDefaults: defaults,
            rememberOriginalSubtitles: { [preferences] in preferences?.setShowsOriginalSubtitles($0, for: item) },
            trickplay: { [client] source in
                guard let session else { return nil }
                return try? await client.trickplay(for: item, versionID: source.versionID, pixelWidth: Self.trickplayWidth, session: session)
            }
        )
    }

    /// How wide, in pixels, the server's pictures for the player's scrubbing preview are best: as the
    /// preview is drawn on a 4K TV, 400 points at 2 pixels each.
    nonisolated static let trickplayWidth = 800

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

    /// A show's episodes, asked ahead of Play on the show: nil if the server couldn't say.
    private struct PreparedEpisodes {
        let finding: Task<[MediaItem]?, Never>
        let asked: ContinuousClock.Instant
    }
}
