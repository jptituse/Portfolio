import Foundation
import PortfolioShared
import PortfolioSharedJellyfinClient
import PortfolioSharedPlaybackEngine
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedUI

@MainActor
struct PlayerViewModelTests {
    let engine = FakePlaybackEngine()
    let stream = PlaybackSource(url: URL(string: "https://media.test/arrival.mkv")!, httpHeaders: ["Authorization": "token"])

    let reports = Reports()

    func player(startingAt position: Duration = .zero, source: @escaping () async throws -> PlaybackSource) -> PlayerViewModel {
        PlayerViewModel(
            title: "Arrival",
            makeEngine: { engine },
            startingAt: position,
            source: source,
            describe: { _ in "Couldn't reach Living Room." },
            reportStarted: { [reports] in reports.started.append(($0, $1)) },
            reportStopped: { [reports] in reports.stopped.append(($0, $1)) }
        )
    }

    /// Waits for the load `start()` began to finish.
    /// Waits until `condition` holds, for up to 5 seconds. The fake engine answers within a few turns,
    /// and the mock server within milliseconds, but longer on a busy machine: 200 turns weren't always
    /// enough when every suite ran at once.
    func waitUntil(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    @Test func opensWhereTheMediaIsAndPlaysIt() async {
        let player = player(startingAt: .seconds(347)) { stream }
        #expect(player.isWaiting)

        player.start()
        await waitUntil { engine.isPlaying }

        #expect(engine.loads.map(\.source) == [stream])
        #expect(engine.loads.map(\.position) == [.seconds(347)])
        #expect(player.status == .playing)
        #expect(!player.isWaiting)
        #expect(player.message == nil)
    }

    @Test func startsOnce() async {
        let player = player { stream }

        player.start()
        player.start()
        await waitUntil { engine.isPlaying }

        #expect(engine.loads.count == 1)
    }

    @Test func saysWhyWhenItCantFindWhereTheMediaIs() async {
        let player = player { throw JellyfinError.unreachable }

        player.start()
        await waitUntil { player.message != nil }

        #expect(player.message == "Couldn't reach Living Room.")
        #expect(player.status == .failed("Couldn't reach Living Room."))
        #expect(engine.loads.isEmpty)
    }

    @Test func saysItCouldntPlayWhenTheEngineCant() async {
        engine.loadFailure = "Invalid data found when processing input"
        let player = player { stream }

        player.start()
        await waitUntil { player.message != nil }

        #expect(player.message == "Couldn't play Arrival.")
        #expect(player.statusName == "failed")
        #expect(!engine.isPlaying)
    }

    @Test func waitsWhileTheEngineSaysItsPausedBeforePlaying() async {
        engine.holdsLoad = true
        let player = player { stream }
        player.start()
        await waitUntil { engine.status == .paused }

        #expect(player.isWaiting)

        engine.finishLoading()
        await waitUntil { engine.isPlaying }
        #expect(!player.isWaiting)

        // Paused once it has played, it isn't waiting.
        player.togglePlayPause()
        #expect(!player.isWaiting)
    }

    @Test func closingStopsTheEngine() async {
        let player = player { stream }
        player.start()
        await waitUntil { engine.isPlaying }

        player.close()

        #expect(engine.isStopped)
    }

    @Test func closingBeforeTheMediaIsFoundPlaysNothing() async {
        let player = player {
            try await Task.sleep(for: .seconds(60))
            return stream
        }
        player.start()

        player.close()
        for _ in 0..<20 { await Task.yield() }

        #expect(engine.loads.isEmpty)
        #expect(player.message == nil)
    }

    // MARK: Reports

    @Test func reportsPlaybackStartingFromWhereItStarts() async {
        let player = player(startingAt: .seconds(347)) { stream }

        player.start()
        await waitUntil { !reports.started.isEmpty }

        #expect(reports.started.map(\.source) == [stream])
        #expect(reports.started.map(\.position) == [.seconds(347)])
    }

    @Test func reportsWherePlaybackStoppedWhenClosed() async {
        let player = player { stream }
        player.start()
        await waitUntil { !reports.started.isEmpty }
        engine.currentTime = .seconds(600)

        player.close()
        await waitUntil { !reports.stopped.isEmpty }

        #expect(reports.stopped.map(\.source) == [stream])
        #expect(reports.stopped.map(\.position) == [.seconds(600)])
    }

    @Test func closesOnce() async {
        let player = player { stream }
        player.start()
        await waitUntil { !reports.started.isEmpty }

        // As Back does, and then the player going away.
        player.close()
        player.close()
        for _ in 0..<20 { await Task.yield() }

        #expect(reports.stopped.count == 1)
    }

    @Test func reportsNothingWhenItNeverStarted() async {
        let player = player { throw JellyfinError.unreachable }
        player.start()
        await waitUntil { player.message != nil }

        player.close()
        for _ in 0..<20 { await Task.yield() }

        #expect(reports.started.isEmpty)
        #expect(reports.stopped.isEmpty)
    }

    @Test func saysPlaybackIsntAvailableWhenItsEngineCantStart() {
        let player = PlayerViewModel(title: "Arrival", source: stream) { throw URLError(.unknown) }

        player.start()

        #expect(player.message == "Playback isn't available right now.")
    }

    // MARK: Controls

    /// A player already playing `duration` of media, from `position`.
    func playingPlayer(duration: Duration = .seconds(7_200), at position: Duration = .seconds(65), controlsTimeout: Duration = .seconds(60)) async -> PlayerViewModel {
        let player = PlayerViewModel(title: "Arrival", makeEngine: { engine }, source: { stream }, describe: { _ in "" }, controlsTimeout: controlsTimeout)
        player.start()
        await waitUntil { engine.isPlaying }
        engine.duration = duration
        engine.currentTime = position
        return player
    }

    @Test func showsItsControlsOnAPressAndHidesThemAgainWhilePlaying() async throws {
        let player = await playingPlayer(controlsTimeout: .milliseconds(30))
        #expect(!player.showsControls)

        player.showControls()
        #expect(player.showsControls)

        try await Task.sleep(for: .milliseconds(200))
        #expect(!player.showsControls)
    }

    @Test func keepsItsControlsWhilePaused() async throws {
        let player = await playingPlayer(controlsTimeout: .milliseconds(30))

        player.togglePlayPause()
        try await Task.sleep(for: .milliseconds(200))

        #expect(player.isPaused)
        #expect(player.showsControls)
    }

    @Test func pausesAndPlays() async {
        let player = await playingPlayer()

        player.togglePlayPause()
        #expect(player.isPaused)
        #expect(engine.status == .paused)

        player.togglePlayPause()
        #expect(!player.isPaused)
        #expect(engine.status == .playing)
    }

    @Test func pausesWhatItWasAskedToPlayEvenWhileTheEngineIsBusy() async {
        let player = await playingPlayer()
        // As an engine does while it seeks.
        engine.status = .buffering

        player.togglePlayPause()

        #expect(player.isPaused)
        #expect(engine.status == .paused)
    }

    @Test func staysPausedWhenPausedOnTheWayToTheSpotPicked() async {
        let player = await playingPlayer(duration: .seconds(100), at: .seconds(20))
        engine.playsAfterSeeking = true
        player.togglePlayPause()
        player.beginScrubbing()
        player.scrub(to: 0.5)

        player.togglePlayPause()
        player.togglePlayPause()
        await waitUntil { engine.currentTime == .seconds(50) }

        #expect(player.isPaused)
        #expect(engine.status == .paused)
    }

    @Test func showsTheSpotPickedAtOnceWhileItGoesThere() async {
        let player = await playingPlayer(duration: .seconds(100), at: .seconds(20))
        player.togglePlayPause()
        player.beginScrubbing()
        player.scrub(to: 0.5)

        player.togglePlayPause()

        #expect(player.position == .seconds(50))
        await waitUntil { engine.currentTime == .seconds(50) }
        #expect(player.position == .seconds(50))
    }

    /// Whether two times are within a millisecond, as times worked out in seconds come.
    func isAbout(_ time: Duration, _ expected: Duration) -> Bool {
        abs((time - expected) / .seconds(1)) < 0.001
    }

    @Test func scrubsWhilePausedAndPlaysFromTheSpotPicked() async {
        let player = await playingPlayer(duration: .seconds(7_200), at: .seconds(40))
        player.togglePlayPause()

        player.beginScrubbing()
        player.scrub(to: 400.0 / 7_200)

        #expect(isAbout(player.position, .seconds(400)))
        // Playback stays where it was until a spot is picked, and the bar still shows where.
        #expect(engine.currentTime == .seconds(40))
        #expect(abs(player.progress - 400.0 / 7_200) < 1e-9)
        #expect(abs(player.playbackProgress - 40.0 / 7_200) < 1e-9)

        player.togglePlayPause()
        let spot = player.position
        await waitUntil { engine.currentTime == spot }
        #expect(engine.currentTime == spot)
        #expect(engine.status == .playing)
        #expect(!player.isScrubbing)
    }

    @Test func keepsTheSpotWithinTheMedia() async {
        let player = await playingPlayer(duration: .seconds(7_200), at: .seconds(40))
        player.togglePlayPause()
        player.beginScrubbing()

        player.scrub(to: -0.2)
        #expect(player.position == .zero)

        player.scrub(to: 1.5)
        #expect(player.position == .seconds(7_200))
    }

    @Test func picksExactlyWherePlaybackIsAtItsMarker() async {
        let player = await playingPlayer(duration: .seconds(7_200), at: .seconds(41))
        player.togglePlayPause()
        player.beginScrubbing()
        player.scrub(to: 0.5)

        player.scrub(to: player.playbackProgress)

        #expect(player.position == .seconds(41))
    }

    @Test func scrubsOnlyOnceItsBegun() async {
        let player = await playingPlayer(duration: .seconds(200), at: .seconds(40))
        player.togglePlayPause()

        player.scrub(to: 0.5)

        #expect(!player.isScrubbing)
        #expect(player.position == .seconds(40))
    }

    @Test func cancellingScrubbingGoesBackToWherePlaybackIs() async {
        let player = await playingPlayer(duration: .seconds(200), at: .seconds(40))
        player.togglePlayPause()
        player.beginScrubbing()
        player.scrub(to: 0.9)

        player.cancelScrubbing()

        #expect(!player.isScrubbing)
        #expect(player.position == .seconds(40))
    }

    @Test func scrubsOnlyWhilePaused() async {
        let player = await playingPlayer()

        player.beginScrubbing()

        #expect(!player.isScrubbing)
    }

    @Test func labelsTheTimeAsTheSystemsPlayerDoes() async {
        let movie = await playingPlayer(duration: .seconds(7_200), at: .seconds(65))
        #expect(movie.elapsedLabel == "01:05")
        #expect(movie.remainingLabel == "-1:58:55")

        engine.currentTime = .seconds(3_725)
        #expect(movie.elapsedLabel == "1:02:05")

        engine.currentTime = .seconds(65)
        engine.duration = .seconds(1_500)
        #expect(movie.elapsedLabel == "01:05")
        #expect(movie.remainingLabel == "-23:55")
    }

    @Test func namesTheShowAndEpisodeAboveAnEpisodesTitle() {
        let episode = MediaItem(
            id: "e5", name: "The Bridge", kind: .episode,
            episode: EpisodeInfo(seriesName: "Severance", seriesID: "s", seasonNumber: 1, episodeNumber: 5)
        )
        let movie = MediaItem(id: "m", name: "Arrival", kind: .movie)

        #expect(PlayerViewModel.subtitle(for: episode) == "Severance · S1E5")
        #expect(PlayerViewModel.subtitle(for: movie) == nil)
    }

    // MARK: From the profile's server

    @Test func playsAnItemFromTheProfilesServerAsItIs() async throws {
        let arrival = MockJellyfinServer.Item(name: "Arrival")
        let mock = MockJellyfinServer(items: [arrival])
        let client = JellyfinServerClient.mocked
        let sessionManager = SessionManager(store: MediaServerStore(storage: InMemorySecureStorage()), authority: client)
        let server = try await client.validateServer(at: mock.url)
        try sessionManager.signIn(try await client.signIn(to: server, username: "alex", password: "hunter2"))
        let profile = CurrentProfileViewModel(client: client, sessionManager: sessionManager)

        let player = profile.makePlayer(for: MediaItem(id: arrival.id, name: "Arrival", kind: .movie), startingAt: .seconds(60)) { engine }
        player.start()
        await waitUntil { engine.isPlaying }

        let load = try #require(engine.loads.first)
        #expect(load.source.url.path() == "/Videos/\(arrival.id)/stream")
        #expect(load.source.httpHeaders["Authorization"]?.contains("Token=") == true)
        #expect(load.position == .seconds(60))

        // The server hears it start, and where it stopped.
        for _ in 0..<200 where mock.playbackReports.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        engine.currentTime = .seconds(75)
        player.close()
        for _ in 0..<200 where mock.playbackReports.count < 2 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(mock.playbackReports.map(\.kind) == [.started, .stopped])
    }

    @Test func playsFromWhatWasFoundAheadOfTime() async throws {
        let arrival = MockJellyfinServer.Item(name: "Arrival")
        let mock = MockJellyfinServer(items: [arrival])
        let client = JellyfinServerClient.mocked
        let sessionManager = SessionManager(store: MediaServerStore(storage: InMemorySecureStorage()), authority: client)
        let server = try await client.validateServer(at: mock.url)
        try sessionManager.signIn(try await client.signIn(to: server, username: "alex", password: "hunter2"))
        let profile = CurrentProfileViewModel(client: client, sessionManager: sessionManager)
        let item = MediaItem(id: arrival.id, name: "Arrival", kind: .movie)

        profile.preparePlayback(of: item)
        profile.preparePlayback(of: item)
        for _ in 0..<200 where mock.playbackInfoRequests.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        let player = profile.makePlayer(for: item) { engine }
        player.start()
        await waitUntil { engine.isPlaying }

        // Asked once, ahead of time.
        #expect(mock.playbackInfoRequests.count == 1)
        #expect(engine.loads.first?.source.url.path() == "/Videos/\(arrival.id)/stream")

        // Each playback is its own play session, so the next one asks again.
        player.close()
        let next = FakePlaybackEngine()
        let again = profile.makePlayer(for: item) { next }
        again.start()
        for _ in 0..<200 where !next.isPlaying {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(mock.playbackInfoRequests.count == 2)
    }

    @Test func saysWhenTheProfilesServerWontSendTheItemAsItIs() async throws {
        var arrival = MockJellyfinServer.Item(name: "Arrival")
        arrival.isDirectlyPlayable = false
        let mock = MockJellyfinServer(name: "Living Room", items: [arrival])
        let client = JellyfinServerClient.mocked
        let sessionManager = SessionManager(store: MediaServerStore(storage: InMemorySecureStorage()), authority: client)
        let server = try await client.validateServer(at: mock.url)
        try sessionManager.signIn(try await client.signIn(to: server, username: "alex", password: "hunter2"))
        let profile = CurrentProfileViewModel(client: client, sessionManager: sessionManager)

        let player = profile.makePlayer(for: MediaItem(id: arrival.id, name: "Arrival", kind: .movie)) { engine }
        player.start()
        await waitUntil { player.message != nil }

        #expect(player.message == "Living Room can't send this as it is, and playing it another way isn't supported yet.")
    }
}

/// What a player told its server, in order.
@MainActor
final class Reports {
    var started: [(source: PlaybackSource, position: Duration)] = []
    var stopped: [(source: PlaybackSource, position: Duration)] = []
}
