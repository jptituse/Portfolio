import Foundation
import Observation
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
    let captionStyles = FakeCaptionStyles()
    /// Each time a player kept whether Style is Original for its item.
    let originals = Recorded<Bool>()
    let preferences = UserDefaults(suiteName: "PlayerViewModelTests-\(UUID().uuidString)")!

    func player(
        startingAt position: Duration = .zero,
        progressInterval: Duration = .seconds(60),
        source: @escaping () async throws -> PlaybackSource
    ) -> PlayerViewModel {
        PlayerViewModel(
            title: "Arrival",
            makeEngine: { engine },
            startingAt: { position },
            source: { _ in try await source() },
            describe: { _ in "Couldn't reach Living Room." },
            reportStarted: { [reports] in reports.started.append(($0, $1)) },
            reportProgress: { [reports] in reports.progress.append(($0, $1, $2)) },
            reportStopped: { [reports] in reports.stopped.append(($0, $1)) },
            progressInterval: progressInterval
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

    @Test func reportsWherePlaybackIsAsItPlays() async {
        let player = player(progressInterval: .milliseconds(20)) { stream }
        player.start()
        await waitUntil { !reports.started.isEmpty }
        engine.currentTime = .seconds(120)

        await waitUntil { reports.progress.count >= 2 }

        #expect(reports.progress.last?.source == stream)
        #expect(reports.progress.last?.position == .seconds(120))
        #expect(reports.progress.last?.isPaused == false)
    }

    @Test func reportsPausingAndPlayingAtOnce() async {
        let player = player { stream }
        player.start()
        await waitUntil { !reports.started.isEmpty }
        engine.currentTime = .seconds(300)

        player.togglePlayPause()
        await waitUntil { reports.progress.count == 1 }
        player.togglePlayPause()
        await waitUntil { reports.progress.count == 2 }

        #expect(reports.progress.map(\.position) == [.seconds(300), .seconds(300)])
        #expect(reports.progress.map(\.isPaused) == [true, false])
    }

    @Test func reportsPlayingFromTheSpotPickedAtOnce() async {
        let player = player { stream }
        player.start()
        await waitUntil { !reports.started.isEmpty }
        engine.duration = .seconds(1_000)
        player.togglePlayPause()
        player.beginScrubbing()
        player.scrub(to: 0.5)

        player.togglePlayPause()
        await waitUntil { reports.progress.count == 2 }

        #expect(reports.progress.last?.position == .seconds(500))
        #expect(reports.progress.last?.isPaused == false)
    }

    @Test func stopsReportingWhereItIsOnceClosed() async throws {
        let player = player(progressInterval: .milliseconds(20)) { stream }
        player.start()
        await waitUntil { !reports.progress.isEmpty }

        player.close()
        await waitUntil { !reports.stopped.isEmpty }
        let reported = reports.progress.count
        try await Task.sleep(for: .milliseconds(100))

        #expect(reports.progress.count == reported)
    }

    @Test func reportsInTheOrderItSendsThem() async {
        let slow = SlowReports()
        let player = PlayerViewModel(
            title: "Arrival",
            makeEngine: { engine },
            source: { _ in stream },
            describe: { _ in "" },
            reportStarted: { _, _ in await slow.record("started") },
            reportProgress: { _, _, isPaused in await slow.record(isPaused ? "paused" : "playing") },
            reportStopped: { _, _ in await slow.record("stopped") }
        )
        player.start()
        await waitUntil { engine.isPlaying }

        player.togglePlayPause()
        player.togglePlayPause()
        player.close()
        await waitUntil { slow.received.count == 4 }

        #expect(slow.received == ["started", "paused", "playing", "stopped"])
    }

    @Test func reportsStoppingAtTheEndWhenItPlayedToTheEnd() async {
        let player = player { stream }
        player.start()
        await waitUntil { !reports.started.isEmpty }
        engine.duration = .seconds(5_400)
        engine.currentTime = .seconds(5_398)

        engine.status = .ended
        player.close()
        await waitUntil { !reports.stopped.isEmpty }

        #expect(reports.stopped.map(\.position) == [.seconds(5_400)])
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
    func playingPlayer(
        duration: Duration = .seconds(7_200),
        at position: Duration = .seconds(65),
        controlsTimeout: Duration = .seconds(60),
        playbackDefaults: PlaybackDefaults = PlaybackDefaults()
    ) async -> PlayerViewModel {
        let player = PlayerViewModel(
            title: "Arrival",
            makeEngine: { engine },
            source: { _ in stream },
            describe: { _ in "" },
            controlsTimeout: controlsTimeout,
            playbackDefaults: playbackDefaults
        )
        player.start()
        await waitUntil { engine.isPlaying }
        engine.duration = duration
        engine.currentTime = position
        await waitUntil { player.position == position }
        return player
    }

    @Test func showsItsControlsOnAPressAndHidesThemAgainWhilePlaying() async {
        let player = await playingPlayer(controlsTimeout: .milliseconds(30))
        #expect(!player.showsControls)

        player.showControls()
        #expect(player.showsControls)

        await waitUntil { !player.showsControls }
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

    @Test func scrubsOnlyWhilePaused() async {
        let player = await playingPlayer()

        player.beginScrubbing()

        #expect(!player.isScrubbing)
    }

    // MARK: Clicking and holding Left and Right

    /// Skips of 10 s back and 30 s on, as Settings could have them.
    let skips = PlaybackDefaults(skipBack: .seconds(10), skipForward: .seconds(30))

    @Test func clickingSkipsBySettingsSkipsAndShowsWhich() async {
        let player = await playingPlayer(at: .seconds(65), playbackDefaults: skips)

        player.click(.forward)
        await waitUntil { engine.currentTime == .seconds(95) }
        #expect(engine.currentTime == .seconds(95))
        #expect(engine.status == .playing)
        #expect(player.showsControls)
        #expect(player.skipHint == PlayerViewModel.SkipHint(direction: .forward, seconds: 30))

        player.click(.back)
        await waitUntil { engine.currentTime == .seconds(85) }
        #expect(engine.currentTime == .seconds(85))
        #expect(player.skipHint == PlayerViewModel.SkipHint(direction: .back, seconds: 10))

        // Until a moment after playback gets there.
        await waitUntil { player.skipHint == nil }
        #expect(player.skipHint == nil)
    }

    @Test func clicksOneAfterAnotherAddUp() async {
        let player = await playingPlayer(at: .seconds(65), playbackDefaults: skips)

        player.click(.forward)
        player.click(.forward)

        await waitUntil { engine.currentTime == .seconds(125) }
        #expect(engine.currentTime == .seconds(125))
    }

    @Test func skipsWithinTheMedia() async {
        let player = await playingPlayer(duration: .seconds(200), at: .seconds(190), playbackDefaults: skips)
        player.click(.forward)
        await waitUntil { engine.currentTime == .seconds(200) }
        #expect(engine.currentTime == .seconds(200))

        engine.currentTime = .seconds(5)
        player.click(.back)
        await waitUntil { engine.currentTime == .zero }
        #expect(engine.currentTime == .zero)
    }

    @Test func pausedWithTheControlsUpAClickMovesTheSpot() async {
        let player = await playingPlayer(at: .seconds(40), playbackDefaults: skips)
        player.togglePlayPause()

        player.click(.forward)
        #expect(player.isScrubbing)
        #expect(player.position == .seconds(50))
        player.click(.back)
        player.click(.back)
        #expect(player.position == .seconds(30))
        // Playback stays where it was until the spot's picked, and the way the spot went shows.
        #expect(engine.currentTime == .seconds(40))
        #expect(player.skipHint == PlayerViewModel.SkipHint(direction: .back, seconds: 10))

        player.togglePlayPause()
        await waitUntil { engine.currentTime == .seconds(30) }
        #expect(engine.currentTime == .seconds(30))
        #expect(engine.status == .playing)
    }

    @Test func pausedWithTheControlsHiddenAClickSkips() async {
        let player = await playingPlayer(at: .seconds(40), playbackDefaults: skips)
        player.togglePlayPause()
        player.hideControls()

        player.click(.forward)

        await waitUntil { engine.currentTime == .seconds(70) }
        #expect(engine.currentTime == .seconds(70))
        #expect(player.isPaused)
        #expect(engine.status == .paused)
        #expect(!player.isScrubbing)
        #expect(player.showsControls)
    }

    @Test func scrubbingAClickMovesTheSpotWithinTheMedia() async {
        let player = await playingPlayer(duration: .seconds(200), at: .seconds(5))
        player.togglePlayPause()
        player.beginScrubbing()

        player.click(.back)
        #expect(player.position == .zero)

        player.scrub(to: 0.99)
        player.click(.forward)
        #expect(player.position == .seconds(200))
    }

    @Test func holdingPausesAndSetsTheNeedleMoving() async {
        let player = await playingPlayer(at: .seconds(100))

        player.hold(.forward)

        #expect(player.isPaused)
        #expect(engine.status == .paused)
        #expect(player.isScrubbing)
        #expect(player.drive?.rate == 8)
        #expect(player.drive?.speed == 1)
        let started = ContinuousClock.now
        await waitUntil { player.position >= .seconds(102) }
        let elapsed = (ContinuousClock.now - started) / .seconds(1)
        // 8 seconds of the media a second, while playback stays put.
        #expect(player.position >= .seconds(102))
        #expect(player.position <= .seconds(100 + 8 * elapsed + 0.5))
        #expect(engine.currentTime == .seconds(100))
    }

    @Test func holdingBackMovesTheNeedleBack() async {
        let player = await playingPlayer(at: .seconds(100))

        player.hold(.back)

        #expect(player.drive?.rate == -8)
        #expect(player.drive?.direction == .back)
        await waitUntil { player.position <= .seconds(98) }
        #expect(player.position <= .seconds(98))
    }

    @Test func aClickWhileTheNeedleMovesChangesItsSpeed() async {
        let player = await playingPlayer(at: .seconds(100))
        player.hold(.forward)

        var rates: [Double?] = []
        for _ in 0..<4 {
            player.click(.forward)
            rates.append(player.drive?.rate)
        }
        #expect(rates == [24, 48, 96, 96])
        #expect(player.drive?.speed == 4)

        rates = []
        for _ in 0..<4 {
            player.click(.back)
            rates.append(player.drive?.rate)
        }
        // Slower, then past the slowest to the slowest the other way.
        #expect(rates == [48, 24, 8, -8])
        #expect(player.drive?.speed == 1)
    }

    @Test func holdingWhileTheNeedleMovesIsAClick() async {
        let player = await playingPlayer(at: .seconds(100))
        player.hold(.forward)

        player.hold(.forward)

        #expect(player.drive?.rate == 24)
    }

    @Test func selectPlaysFromWhereTheNeedleGot() async {
        let player = await playingPlayer(at: .seconds(100))
        player.hold(.forward)
        await waitUntil { player.position >= .seconds(101) }

        player.togglePlayPause()
        let spot = player.position

        #expect(player.drive == nil)
        #expect(!player.isScrubbing)
        #expect(spot >= .seconds(101))
        await waitUntil { engine.currentTime == spot }
        #expect(engine.currentTime == spot)
        #expect(engine.status == .playing)
    }

    @Test func aSwipeTakesOverFromTheNeedle() async throws {
        let player = await playingPlayer(at: .seconds(100))
        player.hold(.forward)
        await waitUntil { player.position >= .seconds(101) }

        player.beginScrubbing()
        let spot = player.position
        try await Task.sleep(for: .milliseconds(100))

        #expect(player.drive == nil)
        #expect(player.isScrubbing)
        #expect(player.position == spot)
    }

    @Test func theNeedleStopsAtAnEnd() async {
        let player = await playingPlayer(duration: .seconds(200), at: .seconds(199))

        player.hold(.forward)

        await waitUntil { player.drive == nil }
        #expect(player.drive == nil)
        #expect(player.isScrubbing)
        #expect(player.position == .seconds(200))
    }

    @Test func showsTheNeedlesSpeedTheSkipOrThePauseBesideTheTime() async {
        typealias Badge = PlayerViewModel.TimeBadge
        let player = await playingPlayer(at: .seconds(65), playbackDefaults: skips)
        #expect(player.timeBadge(isInteracting: false) == nil)

        player.click(.forward)
        #expect(player.timeBadge(isInteracting: false) == Badge(kind: .skip, symbol: "goforward.30", number: nil, side: .trailing))
        // Going back, it's before the time.
        player.click(.back)
        #expect(player.timeBadge(isInteracting: false) == Badge(kind: .skip, symbol: "gobackward.10", number: nil, side: .leading))
        await waitUntil { player.skipHint == nil }

        player.togglePlayPause()
        #expect(player.timeBadge(isInteracting: false) == Badge(kind: .pause, symbol: "pause.circle", number: nil, side: .trailing))
        #expect(player.timeBadge(isInteracting: true) == nil)

        // Paused, a click moves the spot, and shows how far.
        player.click(.forward)
        #expect(player.timeBadge(isInteracting: false) == Badge(kind: .skip, symbol: "goforward.10", number: nil, side: .trailing))
        await waitUntil { player.skipHint == nil }
        #expect(player.timeBadge(isInteracting: false) == Badge(kind: .pause, symbol: "pause.circle", number: nil, side: .trailing))

        player.hold(.back)
        #expect(player.timeBadge(isInteracting: false) == Badge(kind: .drive, symbol: "backward.circle", number: nil, side: .leading))
        player.click(.back)
        #expect(player.timeBadge(isInteracting: false) == Badge(kind: .drive, symbol: "backward.circle", number: "2", side: .leading))
    }

    // MARK: The server's pictures of the spot

    /// A player of Arrival, 2,500 seconds long, from a server with 250 trickplay pictures of it 10 seconds
    /// apart, 4 by 2 pixels each, so a tile of 10 by 10 is 40 by 20. The server stays up while the
    /// test holds it.
    func playerWithTrickplay() async throws -> (PlayerViewModel, MockJellyfinServer) {
        var arrival = MockJellyfinServer.Item(name: "Arrival")
        arrival.trickplay = [.init(width: 4, height: 2, count: 250)]
        let mock = MockJellyfinServer(items: [arrival], imageData: MockJellyfinServer.samplePNG(width: 40, height: 20))
        let client = JellyfinServerClient.mocked
        let session = try await client.signIn(to: try await client.validateServer(at: mock.url), username: "alex", password: "hunter2")
        let item = MediaItem(id: arrival.id, name: "Arrival", kind: .movie)
        let player = PlayerViewModel(
            title: "Arrival",
            makeEngine: { engine },
            source: { _ in stream },
            describe: { _ in "" },
            trickplay: { _ in try? await client.trickplay(for: item, versionID: arrival.id, pixelWidth: 4, session: session) },
            pipeline: ImagePipeline(configuration: MockJellyfinServer.sessionConfiguration)
        )
        player.start()
        await waitUntil { engine.isPlaying }
        engine.duration = .seconds(2_500)
        engine.currentTime = .seconds(65)
        await waitUntil { player.trickplay != nil && player.position == .seconds(65) }
        return (player, mock)
    }

    @Test func showsTheServersPictureOfTheSpotWhileScrubbing() async throws {
        let (player, server) = try await playerWithTrickplay()
        defer { withExtendedLifetime(server) {} }
        #expect(player.trickplay?.count == 250)
        #expect(player.scrubPreview == nil)

        player.togglePlayPause()
        player.click(.forward)
        await waitUntil { player.scrubPreview != nil }
        let first = try #require(player.scrubPreview)
        #expect(first.width == 4)
        #expect(first.height == 2)

        // Another picture, from the same tile, shows at once.
        player.click(.forward)
        #expect(player.scrubPreview !== first)
        #expect(player.scrubPreview?.width == 4)

        player.resume()
        #expect(player.scrubPreview == nil)
    }

    @Test func showsNoPictureWhereTheServerHasNone() async {
        let player = await playingPlayer(at: .seconds(65))

        player.togglePlayPause()
        player.click(.forward)

        #expect(player.isScrubbing)
        #expect(player.trickplay == nil)
        #expect(player.scrubPreview == nil)
    }

    @Test func menuWhilePausedPlaysFromWherePlaybackPaused() async {
        let player = await playingPlayer(at: .seconds(100))
        player.togglePlayPause()
        player.click(.forward)
        player.click(.forward)

        player.resume()

        // The spot picked isn't played from.
        #expect(!player.isScrubbing)
        #expect(!player.isPaused)
        #expect(engine.status == .playing)
        #expect(engine.currentTime == .seconds(100))
        #expect(player.position == .seconds(100))
    }

    @Test func menuWhileTheNeedleMovesPlaysFromWherePlaybackPaused() async {
        let player = await playingPlayer(at: .seconds(100))
        player.hold(.forward)
        await waitUntil { player.position >= .seconds(101) }

        player.resume()

        #expect(player.drive == nil)
        #expect(!player.isScrubbing)
        #expect(engine.status == .playing)
        #expect(engine.currentTime == .seconds(100))
    }

    @Test func saysWhenItsJustBeenPausedWithNothingDoneSince() async {
        let player = await playingPlayer(at: .seconds(100))
        #expect(!player.isPausedUntouched)

        player.togglePlayPause()
        #expect(player.isPausedUntouched)
        player.togglePlayPause()
        #expect(!player.isPausedUntouched)

        // Anything done since: a click, a hold, a swipe, or focus on the menus.
        let actions: [(PlayerViewModel) -> Void] = [
            { $0.click(.forward) },
            { $0.hold(.back) },
            { $0.beginScrubbing() },
            { $0.holdControls(true) },
        ]
        for action in actions {
            if !player.isPaused { player.togglePlayPause() }
            player.resume()
            player.togglePlayPause()
            #expect(player.isPausedUntouched)
            action(player)
            #expect(!player.isPausedUntouched)
            player.holdControls(false)
        }
    }

    @Test func menuWhileScrubbingPutsTheSpotBackStillPaused() async {
        let player = await playingPlayer(at: .seconds(100))
        player.togglePlayPause()
        player.click(.forward)
        player.hold(.forward)

        player.cancelScrubbing()

        #expect(!player.isScrubbing)
        #expect(player.drive == nil)
        #expect(player.isPaused)
        #expect(player.position == .seconds(100))
        // Something's been done since pausing: Menu again plays on, rather than leaving.
        #expect(!player.isPausedUntouched)
    }

    @Test func pausesWhenTheAppGoesToTheBackground() async {
        let player = await playingPlayer(at: .seconds(100))
        player.hideControls()

        player.enteredBackground()

        #expect(player.isPaused)
        #expect(player.isPausedUntouched)
        #expect(engine.status == .paused)
        #expect(player.showsControls)
    }

    @Test func clicksAndHoldsWaitForTheMedia() {
        let player = PlayerViewModel(title: "Arrival", makeEngine: { engine }, source: { _ in stream }, describe: { _ in "" })

        player.click(.forward)
        player.hold(.forward)

        #expect(!player.isScrubbing)
        #expect(player.drive == nil)
        #expect(player.skipHint == nil)
    }

    @Test func labelsTheTimeAsTheSystemsPlayerDoes() async {
        let movie = await playingPlayer(duration: .seconds(7_200), at: .seconds(65))
        #expect(movie.elapsedLabel == "01:05")
        #expect(movie.remainingLabel == "-1:58:55")

        engine.currentTime = .seconds(3_725)
        await waitUntil { movie.elapsedLabel != "01:05" }
        #expect(movie.elapsedLabel == "1:02:05")

        engine.currentTime = .seconds(65)
        engine.duration = .seconds(1_500)
        await waitUntil { movie.elapsedLabel != "1:02:05" }
        #expect(movie.elapsedLabel == "01:05")
        #expect(movie.remainingLabel == "-23:55")
    }

    @Test func showsTheTimeOtherwiseInAnotherSecondOrAStepOfTheBarOn() {
        let movie = Duration.seconds(7_200)
        #expect(!PlayerViewModel.shows(.milliseconds(65_999), otherwiseThan: .seconds(65), in: movie))
        #expect(PlayerViewModel.shows(.seconds(66), otherwiseThan: .milliseconds(65_999), in: movie))
        #expect(PlayerViewModel.shows(.seconds(64), otherwiseThan: .seconds(65), in: movie))
        // A step of the bar is a 2,000th of a video 20 seconds long: 10 milliseconds.
        let clip = Duration.seconds(20)
        #expect(!PlayerViewModel.shows(.milliseconds(5_009), otherwiseThan: .seconds(5), in: clip))
        #expect(PlayerViewModel.shows(.milliseconds(5_011), otherwiseThan: .seconds(5), in: clip))
        #expect(!PlayerViewModel.shows(.milliseconds(5_500), otherwiseThan: .seconds(5), in: .zero))
    }

    /// The engine's time changes about 10 times a second, and everything showing the time is drawn
    /// again whenever what it reads changes.
    @Test func changesTheTimeItShowsOnlyWhenWhatItShowsWouldChange() async {
        let movie = await playingPlayer(duration: .seconds(7_200), at: .seconds(65))
        let changes = TimeChanges()
        changes.watch(movie)

        engine.currentTime = .milliseconds(65_400)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(changes.count == 0)

        engine.currentTime = .seconds(66)
        await waitUntil { changes.count > 0 }
        #expect(movie.elapsedLabel == "01:06")
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

    /// The profile of someone signed in to `mock`.
    func profile(on mock: MockJellyfinServer, defaults: UserDefaults = .forTesting()) async throws -> CurrentProfileViewModel {
        let client = JellyfinServerClient.mocked
        let sessionManager = SessionManager(store: MediaServerStore(storage: InMemorySecureStorage()), authority: client)
        let server = try await client.validateServer(at: mock.url)
        try sessionManager.signIn(try await client.signIn(to: server, username: "alex", password: "hunter2"))
        return CurrentProfileViewModel(client: client, sessionManager: sessionManager, devicePreferences: DevicePreferences(defaults: .forTesting()), defaults: defaults)
    }

    @Test func keepsOriginalForTheItemThePlayerPlays() async throws {
        let arrival = MockJellyfinServer.Item(name: "Arrival")
        let mock = MockJellyfinServer(items: [arrival])
        let profile = try await profile(on: mock)
        let item = MediaItem(id: arrival.id, name: "Arrival", kind: .movie)
        let player = profile.makePlayer(for: item) { engine }
        #expect(!player.showsOriginalSubtitles)

        player.chooseOriginalSubtitles()

        #expect(profile.preferences?.showsOriginalSubtitles(for: item) == true)
        #expect(profile.makePlayer(for: item) { FakePlaybackEngine() }.showsOriginalSubtitles)
        let dune = MediaItem(id: "dune", name: "Dune", kind: .movie)
        #expect(!profile.makePlayer(for: dune) { FakePlaybackEngine() }.showsOriginalSubtitles)
    }

    @Test func playsAnItemFromTheProfilesServerAsItIs() async throws {
        let arrival = MockJellyfinServer.Item(name: "Arrival")
        let mock = MockJellyfinServer(items: [arrival])
        let profile = try await profile(on: mock)

        let player = profile.makePlayer(for: MediaItem(id: arrival.id, name: "Arrival", kind: .movie)) { engine }
        player.start()
        await waitUntil { engine.isPlaying }

        let load = try #require(engine.loads.first)
        #expect(load.source.url.path() == "/Videos/\(arrival.id)/stream")
        #expect(load.source.httpHeaders["Authorization"]?.contains("Token=") == true)
        #expect(load.position == .zero)

        // The server hears it start, where it is when it pauses, and where it stopped.
        await waitUntil { !mock.playbackReports.isEmpty }
        engine.currentTime = .seconds(75)
        player.togglePlayPause()
        player.close()
        await waitUntil { mock.playbackReports.count == 3 }
        #expect(mock.playbackReports.map(\.kind) == [.started, .progress, .stopped])
    }

    @Test func resumesWhereTheServerSaysTheUserGotToWhenPlayIsPressed() async throws {
        var arrival = MockJellyfinServer.Item(name: "Arrival")
        arrival.watchedMinutes = 25
        let mock = MockJellyfinServer(items: [arrival])
        let profile = try await profile(on: mock)
        // Loaded before they watched more of it somewhere else.
        let item = MediaItem(id: arrival.id, name: "Arrival", kind: .movie, userData: UserData(playbackPosition: .seconds(600)))

        let player = profile.makePlayer(for: item, from: .resuming) { engine }
        player.start()
        await waitUntil { engine.isPlaying }

        #expect(engine.loads.map(\.position) == [.seconds(25 * 60)])
    }

    @Test func startsFromTheBeginningWhenAskedToWhereverTheUserGotTo() async throws {
        var arrival = MockJellyfinServer.Item(name: "Arrival")
        arrival.watchedMinutes = 25
        let mock = MockJellyfinServer(items: [arrival])
        let profile = try await profile(on: mock)
        let item = MediaItem(id: arrival.id, name: "Arrival", kind: .movie, userData: UserData(playbackPosition: .seconds(25 * 60)))

        let player = profile.makePlayer(for: item, from: .beginning) { engine }
        player.start()
        await waitUntil { engine.isPlaying }

        #expect(engine.loads.map(\.position) == [.zero])
    }

    @Test func knowsWhereTheUserGotToOnceItHasStopped() async throws {
        let arrival = MockJellyfinServer.Item(name: "Arrival")
        let mock = MockJellyfinServer(items: [arrival])
        let profile = try await profile(on: mock)
        let item = MediaItem(id: arrival.id, name: "Arrival", kind: .movie)
        let player = profile.makePlayer(for: item) { engine }
        player.start()
        await waitUntil { engine.isPlaying }
        #expect(!profile.userDataUpdates.userData(for: item).canResume)

        // Where the server saves it, as it hears playback stop.
        mock.items[0].watchedMinutes = 42
        mock.items[0].lastPlayed = .now
        player.close()
        await waitUntil { profile.userDataUpdates.userData(for: item).canResume }

        #expect(profile.userDataUpdates.userData(for: item).playbackPosition == .seconds(42 * 60))
    }

    @Test func playsFromWhatWasFoundAheadOfTime() async throws {
        let arrival = MockJellyfinServer.Item(name: "Arrival")
        let mock = MockJellyfinServer(items: [arrival])
        let profile = try await profile(on: mock)
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

    @Test func saysWhenTheProfilesServerWontSendTheItemEitherWay() async throws {
        var arrival = MockJellyfinServer.Item(name: "Arrival")
        arrival.isDirectlyPlayable = false
        arrival.isTranscodable = false
        let mock = MockJellyfinServer(name: "Living Room", items: [arrival])
        let profile = try await profile(on: mock)

        let player = profile.makePlayer(for: MediaItem(id: arrival.id, name: "Arrival", kind: .movie)) { engine }
        player.start()
        await waitUntil { player.message != nil }

        #expect(player.message == "Living Room can't send this in a form that plays here.")
    }

    @Test func playsTheStreamTheProfilesServerMakesWhenItWontSendTheFileAsItIs() async throws {
        var arrival = MockJellyfinServer.Item(name: "Arrival")
        arrival.isDirectlyPlayable = false
        let mock = MockJellyfinServer(items: [arrival])
        let profile = try await profile(on: mock)

        let player = profile.makePlayer(for: MediaItem(id: arrival.id, name: "Arrival", kind: .movie)) { engine }
        player.start()
        await waitUntil { engine.isPlaying }

        #expect(engine.loads.first?.source.method == .transcode)
        #expect(engine.loads.first?.source.url.path() == "/videos/\(arrival.id)/master.m3u8")
    }

    @Test func aLowerQualityPlaysTheProfilesServersStreamAndAutoStopsIt() async throws {
        let arrival = MockJellyfinServer.Item(name: "Arrival")
        let mock = MockJellyfinServer(items: [arrival])
        let profile = try await profile(on: mock)
        let player = profile.makePlayer(for: MediaItem(id: arrival.id, name: "Arrival", kind: .movie)) { engine }
        player.start()
        await waitUntil { engine.isPlaying }
        engine.currentTime = .seconds(600)

        player.selectQuality(.maxBitrate(8_000_000))
        await waitUntil { engine.loads.count == 2 && engine.isPlaying }
        let stream = try #require(engine.loads.last?.source)
        #expect(stream.method == .transcode)
        #expect(engine.loads.last?.position == .seconds(600))

        player.selectQuality(.auto)
        await waitUntil { mock.stoppedTranscodes.count == 1 }
        #expect(engine.loads.last?.source.method == .directPlay)
        #expect(mock.stoppedTranscodes == [stream.playSessionID])
    }

    // MARK: Tracks and quality

    /// A film playing as it is, with audio and subtitles in it, a subtitle file and tracks only a stream
    /// the server makes carries.
    let film = PlaybackSource(
        url: URL(string: "https://media.test/arrival.mkv")!,
        versionID: "arrival",
        playSessionID: "session-1",
        audioTracks: [
            MediaTrack(id: 3, title: "English - Dolby Digital+ - 5.1 - Default", language: "eng", isDefault: true, isText: false),
            MediaTrack(id: 4, title: "Spanish - AAC - Stereo", language: "spa", isText: false),
            MediaTrack(id: 7, title: "Commentary - AAC - Stereo - External", isText: false, delivery: .transcoded),
        ],
        subtitleTracks: [
            MediaTrack(id: 0, title: "English - SDH - SRT - External", delivery: .file(URL(string: "https://media.test/0.srt")!)),
            MediaTrack(id: 1, title: "French - PGSSUB - External", isText: false, delivery: .transcoded),
            MediaTrack(id: 5, title: "English - SUBRIP", isDefault: true),
            MediaTrack(id: 6, title: "Spanish - PGSSUB", isText: false),
        ],
        audioTrack: 3,
        bitrate: 20_000_000
    )

    /// A player playing `film`, from `position`, whose server makes a stream for each request after the
    /// first, unless `failsAfterStarting`.
    func filmPlayer(
        at position: Duration = .seconds(65),
        failsAfterStarting: Bool = false,
        source: PlaybackSource? = nil,
        defaults: PlaybackDefaults = PlaybackDefaults()
    ) async -> (PlayerViewModel, Streams) {
        let streams = Streams(first: source ?? film, failsAfterFirst: failsAfterStarting)
        let player = PlayerViewModel(
            title: "Arrival",
            makeEngine: { engine },
            source: { [streams] in try await streams.source(for: $0) },
            describe: { _ in "" },
            stopTranscoding: { [streams] in streams.stopped.append($0) },
            reportStarted: { [reports] in reports.started.append(($0, $1)) },
            reportProgress: { [reports] in reports.progress.append(($0, $1, $2)) },
            reportStopped: { [reports] in reports.stopped.append(($0, $1)) },
            captionStyles: captionStyles.styles,
            preferences: preferences,
            playbackDefaults: defaults,
            rememberOriginalSubtitles: { [originals] in originals.values.append($0) }
        )
        player.start()
        await waitUntil { engine.isPlaying }
        engine.currentTime = position
        return (player, streams)
    }

    // MARK: Settings

    @Test func startsInSettingsAudioLanguageInTheFileAsItIs() async {
        let (player, streams) = await filmPlayer(defaults: PlaybackDefaults(audioLanguage: .language("spa")))

        #expect(player.audioTrack == 4)
        #expect(engine.loads.first?.source.audioTrack == 4)
        // Changed in the file, without asking the server again.
        #expect(streams.requests == [PlaybackRequest()])
    }

    @Test func startsOnTheTrackTheFileMarksForOriginal() async {
        var spanish = film
        spanish.audioTrack = 4
        let (player, _) = await filmPlayer(source: spanish, defaults: PlaybackDefaults(audioLanguage: .original))

        #expect(player.audioTrack == 3)
    }

    @Test func keepsTheServersPickWithoutATrackInSettingsLanguage() async {
        let (player, streams) = await filmPlayer(defaults: PlaybackDefaults(audioLanguage: .language("jpn")))

        #expect(player.audioTrack == 3)
        #expect(streams.requests.count == 1)
    }

    @Test func asksAgainForAStreamTheServerMakesInSettingsLanguageAndStopsTheFirst() async {
        let stream = PlaybackSource(
            url: URL(string: "https://media.test/master.m3u8")!,
            versionID: "arrival",
            playSessionID: "session-1",
            method: .transcode,
            audioTracks: film.audioTracks,
            subtitleTracks: film.subtitleTracks,
            audioTrack: 3
        )

        let (player, streams) = await filmPlayer(source: stream, defaults: PlaybackDefaults(audioLanguage: .language("spa")))

        #expect(streams.requests == [PlaybackRequest(), PlaybackRequest(versionID: "arrival", audioTrack: 4, subtitles: .off)])
        #expect(streams.stopped.map(\.playSessionID) == ["session-1"])
        #expect(engine.loads.count == 1)
        #expect(player.audioTrack == 4)
    }

    @Test func showsSubtitlesInSettingsLanguageWhereTheServerWouldShowSome() async {
        let languages = PlaybackSource(
            url: film.url,
            versionID: "arrival",
            audioTracks: film.audioTracks,
            subtitleTracks: [
                MediaTrack(id: 5, title: "English - SUBRIP", language: "eng", isDefault: true),
                MediaTrack(id: 8, title: "Spanish - Forced - SUBRIP", language: "spa", isForced: true),
                MediaTrack(id: 9, title: "Spanish - SUBRIP", language: "spa"),
            ],
            audioTrack: 3,
            subtitleTrack: 5
        )

        let (player, streams) = await filmPlayer(source: languages, defaults: PlaybackDefaults(subtitleLanguage: "spa"))

        #expect(player.showsSubtitles)
        #expect(player.subtitleTrack == 9)
        #expect(streams.requests.count == 1)
    }

    @Test func showsNoSubtitlesForSettingsWhereTheServerWouldShowNone() async {
        let (player, _) = await filmPlayer(defaults: PlaybackDefaults(subtitleLanguage: "spa"))

        #expect(!player.showsSubtitles)
    }

    @Test func streamsAutoNoFasterThanSettingsSay() async {
        let (player, streams) = await filmPlayer(at: .seconds(600), defaults: PlaybackDefaults(autoMaxBitrate: 10_000_000))
        #expect(streams.requests.first == PlaybackRequest(maxBitrate: 10_000_000))

        player.selectQuality(.maxBitrate(4_000_000))
        await waitUntil { engine.loads.count == 2 && engine.isPlaying }
        player.selectQuality(.auto)
        await waitUntil { streams.requests.count == 3 }

        #expect(streams.requests.last?.maxBitrate == 10_000_000)
        #expect(streams.requests.last?.playsOriginal == false)
    }

    @Test func listsTheTracksAndWhatsPlaying() async {
        let (player, _) = await filmPlayer()

        #expect(player.audioTracks.map(\.id) == [3, 4, 7])
        #expect(player.audioTrack == 3)
        #expect(player.subtitleTracks.map(\.id) == [0, 1, 5, 6])
        #expect(!player.showsSubtitles)
        // On would show the ones the media marks.
        #expect(player.subtitleTrack == 5)
    }

    @Test func switchesAudioInTheFilePlayingAsItIs() async {
        let (player, streams) = await filmPlayer()

        player.selectAudioTrack(4)

        #expect(engine.audioTrackChoices == [4])
        #expect(player.audioTrack == 4)
        #expect(streams.requests.count == 1)
        await waitUntil { !reports.progress.isEmpty }
        #expect(reports.progress.last?.source.audioTrack == 4)
    }

    @Test func asksForAStreamWithAudioOnlyTheServerCanAdd() async {
        let (player, streams) = await filmPlayer(at: .seconds(600))

        player.selectAudioTrack(7)
        await waitUntil { engine.loads.count == 2 && engine.isPlaying }

        #expect(streams.requests.last == PlaybackRequest(versionID: "arrival", audioTrack: 7, subtitles: .off, startPosition: .seconds(600)))
        #expect(engine.loads.last?.position == .seconds(600))
        #expect(player.audioTrack == 7)
        #expect(engine.audioTrackChoices.isEmpty)
    }

    @Test func turnsSubtitlesOnAndOffInTheStream() async {
        let (player, streams) = await filmPlayer()

        player.showSubtitles(true)
        #expect(player.showsSubtitles)
        #expect(player.subtitleTrack == 5)
        player.selectSubtitleTrack(0)
        player.showSubtitles(false)
        #expect(!player.showsSubtitles)
        // On again shows the ones shown last.
        #expect(player.subtitleTrack == 0)
        player.showSubtitles(true)

        #expect(engine.subtitleTrackChoices == [5, 0, nil, 0])
        #expect(streams.requests.count == 1)
    }

    @Test func asksForAStreamToDrawSubtitlesInAndAnotherToTakeThemOut() async {
        let (player, streams) = await filmPlayer(defaults: original)

        player.selectSubtitleTrack(1)
        await waitUntil { engine.loads.count == 2 }
        #expect(streams.requests.last?.subtitles == .track(1))
        #expect(player.subtitleTrack == 1)

        player.showSubtitles(false)
        await waitUntil { engine.loads.count == 3 }
        #expect(streams.requests.last?.subtitles == .off)
        #expect(!player.showsSubtitles)
    }

    @Test func offersAutoOriginalThenTheBitratesBelowTheFiles() async {
        let (player, _) = await filmPlayer()

        #expect(player.qualities.map(\.name) == ["Auto", "Original", "15 Mbps", "10 Mbps", "8 Mbps", "6 Mbps", "4 Mbps", "3 Mbps", "1.5 Mbps", "720 kbps", "420 kbps"])
        #expect(player.quality == .auto)
    }

    @Test func offersEveryBitrateWhenTheFilesIsntKnown() {
        #expect(PlaybackQuality.choices(forBitrate: nil).count == PlaybackQuality.bitrates.count + 2)
        #expect(PlaybackQuality.choices(forBitrate: nil)[2].name == "120 Mbps")
    }

    @Test func originalAsksForNothingWhileTheFilePlaysAsItIs() async {
        let (player, streams) = await filmPlayer()

        player.selectQuality(.original)

        #expect(player.quality == .original)
        #expect(streams.requests.count == 1)
        #expect(engine.loads.count == 1)
    }

    @Test func originalPlaysTheFileWhereTheServerMadeAStream() async {
        let stream = PlaybackSource(
            url: URL(string: "https://media.test/master-1.m3u8")!,
            versionID: "arrival",
            playSessionID: "session-1",
            method: .transcode,
            audioTracks: film.audioTracks,
            subtitleTracks: film.subtitleTracks,
            audioTrack: 3,
            bitrate: 20_000_000
        )
        let (player, streams) = await filmPlayer(at: .seconds(600), source: stream)

        player.selectQuality(.original)
        await waitUntil { engine.loads.count == 2 && !streams.stopped.isEmpty }

        #expect(streams.requests.last == PlaybackRequest(versionID: "arrival", audioTrack: 3, subtitles: .off, playsOriginal: true, startPosition: .seconds(600)))
        #expect(engine.loads.last?.source.method == .directPlay)
        #expect(engine.loads.last?.position == .seconds(600))
        #expect(player.quality == .original)
        #expect(streams.stopped.map(\.playSessionID) == ["session-1"])
    }

    @Test func autoGoesOnPlayingTheFileTheServerWouldSendAsItIs() async {
        let (player, streams) = await filmPlayer()
        player.selectQuality(.original)

        player.selectQuality(.auto)
        await waitUntil { player.quality == .auto }

        #expect(streams.requests.last?.playsOriginal == false)
        #expect(engine.loads.count == 1)
        #expect(streams.stopped.isEmpty)
    }

    @Test func playsALowerQualityFromWherePlaybackIsAndStopsNothingItPlayedAsItIs() async {
        let (player, streams) = await filmPlayer(at: .seconds(600))
        player.selectAudioTrack(4)

        player.selectQuality(.maxBitrate(8_000_000))
        await waitUntil { engine.loads.count == 2 && engine.isPlaying && !streams.stopped.isEmpty }

        #expect(streams.requests.last == PlaybackRequest(versionID: "arrival", audioTrack: 4, subtitles: .off, maxBitrate: 8_000_000, startPosition: .seconds(600)))
        #expect(engine.loads.last?.position == .seconds(600))
        #expect(player.quality == .maxBitrate(8_000_000))
        // The server's client stops only a stream it made.
        #expect(streams.stopped.map(\.playSessionID) == ["session-1"])
        await waitUntil { reports.progress.last?.source.method == .transcode }
        #expect(reports.progress.last?.source.playSessionID == "session-2")
    }

    @Test func stopsTheStreamItMovesOnFrom() async {
        let (player, streams) = await filmPlayer()
        player.selectQuality(.maxBitrate(8_000_000))
        await waitUntil { engine.loads.count == 2 }

        player.selectQuality(.auto)
        await waitUntil { streams.stopped.count == 2 }

        #expect(streams.requests.last?.maxBitrate == nil)
        #expect(streams.stopped.last?.playSessionID == "session-2")
        #expect(player.quality == .auto)
    }

    @Test func playsOnWhenTheServerCantSendAnotherStream() async {
        let (player, streams) = await filmPlayer(failsAfterStarting: true)

        player.selectQuality(.maxBitrate(8_000_000))
        await waitUntil { streams.requests.count == 2 }
        for _ in 0..<20 { await Task.yield() }

        #expect(engine.loads.count == 1)
        #expect(engine.isPlaying)
        #expect(player.quality == .auto)
    }

    @Test func staysPausedThroughAChangeOfStream() async {
        let (player, _) = await filmPlayer()
        player.togglePlayPause()

        player.selectQuality(.maxBitrate(8_000_000))
        await waitUntil { engine.loads.count == 2 }
        for _ in 0..<20 { await Task.yield() }

        #expect(player.isPaused)
        #expect(!engine.isPlaying)
    }

    @Test func stopsAStreamItWontPlayAfterAll() async {
        let (player, streams) = await filmPlayer()
        streams.holdsRequests = true

        player.selectQuality(.maxBitrate(8_000_000))
        await waitUntil { streams.requests.count == 2 }
        player.close()
        streams.releaseRequests()
        await waitUntil { streams.stopped.count == 1 }

        #expect(engine.loads.count == 1)
        #expect(streams.stopped.map(\.playSessionID) == ["session-2"])
    }

    @Test func staysWherePlaybackWasWhileTheNextStreamOpens() async {
        engine.duration = .seconds(7_200)
        let (player, _) = await filmPlayer(at: .seconds(600))
        engine.currentTime = .seconds(601)
        await waitUntil { player.position == .seconds(601) }
        engine.holdsLoad = true

        player.selectQuality(.maxBitrate(8_000_000))
        await waitUntil { engine.loads.count == 2 }
        // Opening another stream, AetherEngine says it's at the start, and doesn't yet know how long it is.
        engine.currentTime = .zero
        engine.duration = .zero
        #expect(player.position == .seconds(601))
        #expect(player.duration == .seconds(7_200))
        #expect(player.progress == 601.0 / 7_200)
        #expect(player.remainingLabel == "-1:49:59")

        player.close()
        engine.finishLoading()
        await waitUntil { !reports.stopped.isEmpty }
        #expect(reports.stopped.map(\.position) == [.seconds(601)])
    }

    // MARK: Menus

    func item(_ id: PlayerMenu.Item.ID, in menu: PlayerMenu?) throws -> PlayerMenu.Item {
        try #require(menu?.sections.flatMap(\.items).first { $0.id == id })
    }

    @Test func listsTheMenusInTheSystemPlayersOrder() async {
        let (player, _) = await filmPlayer()
        #expect(player.menus.map(\.id) == ["subtitles", "audio", "more"])
        #expect(player.menus.map(\.title) == ["Subtitles", "Audio", "More"])
    }

    @Test func leavesOutSubtitlesWithoutAny() async {
        let (player, _) = await filmPlayer(source: PlaybackSource(url: film.url, audioTracks: film.audioTracks, audioTrack: 3))
        #expect(player.menus.map(\.id) == ["audio", "more"])
    }

    @Test func theAudioMenuHasReduceLoudSoundsThenTheTracks() async throws {
        let (player, _) = await filmPlayer()
        let audio = try #require(player.menus.first { $0.id == "audio" })

        #expect(audio.sections.map(\.header) == ["Audio Adjustments", "Audio Track"])
        #expect(audio.sections[0].items.map(\.title) == ["Reduce Loud Sounds"])
        #expect(audio.sections[1].items.map(\.title) == film.audioTracks.map(\.title))
        #expect(audio.sections[1].items.map(\.isChecked) == [true, false, false])
    }

    @Test func reducingLoudSoundsStaysInTheMenuAndIsRemembered() async throws {
        let (player, _) = await filmPlayer()
        player.openMenu("audio")

        player.choose(try item("reduceLoudSounds", in: player.openMenu))

        #expect(player.openMenu?.id == "audio")
        #expect(try item("reduceLoudSounds", in: player.openMenu).isChecked)
        #expect(engine.reducesLoudSounds)
        // The next player starts with it.
        let next = FakePlaybackEngine()
        _ = PlayerViewModel(title: "Arrival", makeEngine: { next }, source: { _ in film }, describe: { _ in "" }, preferences: preferences)
        #expect(next.reducesLoudSounds)
    }

    @Test func choosingATrackClosesTheMenu() async throws {
        let (player, _) = await filmPlayer()
        player.openMenu("audio")

        player.choose(try item("4", in: player.openMenu))

        #expect(player.openMenu == nil)
        #expect(player.openMenuRoot == nil)
        #expect(engine.audioTrackChoices == [4])
    }

    @Test func theSubtitlesMenuHasOnAndOffThenLanguageAndStyle() async throws {
        let (player, _) = await filmPlayer()
        let subtitles = try #require(player.menus.first { $0.id == "subtitles" })

        #expect(subtitles.sections.map(\.header) == ["Subtitles", nil])
        #expect(subtitles.sections[0].items.map(\.title) == ["On", "Off"])
        #expect(subtitles.sections[0].items.map(\.isChecked) == [false, true])
        #expect(subtitles.sections[1].items.map(\.title) == ["Language", "Style"])
        // What On shows, and the style chosen.
        #expect(subtitles.sections[1].items.map(\.detail) == ["English - SUBRIP", "Transparent Background"])
    }

    @Test func aSubmenuOpensInPlaceOnWhatsChosenAndBackReturnsToWhereItOpened() async throws {
        let (player, _) = await filmPlayer()

        player.openMenu("subtitles")
        #expect(player.menuFocus == "on")
        #expect(player.openMenuDepth == 1)

        player.choose(try item("language", in: player.openMenu))
        #expect(player.openMenu?.id == "subtitles.language")
        #expect(player.openMenu?.sections.map(\.header) == ["Language"])
        #expect(player.openMenuRoot == "subtitles")
        #expect(player.menuFocus == "5")
        #expect(player.openMenuDepth == 2)

        player.goBackInMenu()
        #expect(player.openMenu?.id == "subtitles")
        #expect(player.menuFocus == "language")
        #expect(player.openMenuDepth == 1)

        player.goBackInMenu()
        #expect(player.openMenu == nil)
        #expect(player.openMenuRoot == nil)
        #expect(player.openMenuDepth == 0)
    }

    @Test func findsAnyMenuOrSubmenuOpenOrNot() async throws {
        let (player, _) = await filmPlayer()

        #expect(player.menu("audio")?.title == "Audio")
        #expect(player.menu("more.quality")?.sections.map(\.header) == ["Quality"])
        #expect(player.menu("subtitles.language")?.title == "Language")
        #expect(player.menu("nothing") == nil)
    }

    @Test func choosingSubtitlesInLanguageShowsThem() async throws {
        let (player, _) = await filmPlayer()
        player.openMenu("subtitles")
        player.choose(try item("language", in: player.openMenu))

        player.choose(try item("0", in: player.openMenu))

        #expect(player.openMenu == nil)
        #expect(player.showsSubtitles)
        #expect(engine.subtitleTrackChoices == [0])
    }

    @Test func choosingAStyleChoosesItForEveryAppAndShowsHowEachLooks() async throws {
        let (player, _) = await filmPlayer()
        player.openMenu("subtitles")
        player.choose(try item("style", in: player.openMenu))
        #expect(player.openMenu?.sections.flatMap(\.items).map(\.title) == ["Original", "Classic", "Large Text", "Transparent Background"])
        #expect(player.menuFocus == "transparent")
        #expect(try item("large", in: player.openMenu).captionStyle?.sizeScale == 1.5)

        player.choose(try item("large", in: player.openMenu))

        #expect(captionStyles.chosen == "large")
        #expect(player.openMenu == nil)
        let subtitles = try #require(player.menus.first { $0.id == "subtitles" })
        #expect(try item("style", in: subtitles).detail == "Large Text")
    }

    // MARK: Original

    /// `film`, showing the Spanish subtitles drawn as pictures in the file.
    var filmWithPictureSubtitles: PlaybackSource {
        var source = film
        source.subtitleTrack = 6
        return source
    }

    let original = PlaybackDefaults(showsOriginalSubtitles: true)

    @Test func styleOffersOriginalChosenOnlyOnceItsPickedAndKeepsItForTheItem() async throws {
        let (player, _) = await filmPlayer()
        player.openMenu("subtitles")
        player.choose(try item("style", in: player.openMenu))
        #expect(try item("original", in: player.openMenu).captionStyle == .original)
        #expect(player.openMenu?.sections.flatMap(\.items).filter(\.isChecked).map(\.id) == ["transparent"])

        player.choose(try item("original", in: player.openMenu))

        #expect(player.showsOriginalSubtitles)
        #expect(originals.values == [true])
        let subtitles = try #require(player.menus.first { $0.id == "subtitles" })
        #expect(try item("style", in: subtitles).detail == "Original")
        let style = try #require(player.menu("subtitles.style"))
        #expect(style.sections.flatMap(\.items).filter(\.isChecked).map(\.id) == ["original"])
        // The system's style stays as it was.
        #expect(captionStyles.chosen == "transparent")

        player.chooseCaptionStyle("large")
        #expect(originals.values == [true, false])
    }

    @Test func startsOnOriginalWhereTheItemWasLastPlayedWithIt() async {
        let (player, _) = await filmPlayer(source: filmWithPictureSubtitles, defaults: original)

        #expect(player.showsOriginalSubtitles)
        #expect(player.showsSubtitles)
        #expect(player.subtitleTrack == 6)
        #expect(originals.values.isEmpty)
    }

    @Test func startsWithSubtitlesDrawnAsPicturesChosenButOffWithoutOriginal() async throws {
        let (player, streams) = await filmPlayer(source: filmWithPictureSubtitles)

        #expect(!player.showsSubtitles)
        #expect(engine.loads.first?.source.subtitleTrack == nil)
        #expect(streams.requests.count == 1)
        #expect(player.subtitleTrack == 6)
        let language = try #require(player.menu("subtitles.language"))
        #expect(language.sections.flatMap(\.items).filter(\.isChecked).map(\.id) == ["6"])

        // Original never turns them on itself; On does.
        player.chooseOriginalSubtitles()
        #expect(!player.showsSubtitles)
        player.showSubtitles(true)
        #expect(player.showsSubtitles)
        #expect(engine.subtitleTrackChoices == [6])
    }

    @Test func asksAgainWithoutSubtitlesTheServerWouldDrawIntoThePicture() async {
        var burnedIn = film
        burnedIn.subtitleTrack = 1
        let (player, streams) = await filmPlayer(source: burnedIn)

        #expect(streams.requests.last == PlaybackRequest(versionID: "arrival", audioTrack: 3, subtitles: .off))
        #expect(!player.showsSubtitles)
    }

    @Test func choosingSubtitlesDrawnAsPicturesWithoutOriginalKeepsTheStyleAndThemOff() async {
        let (player, _) = await filmPlayer()
        player.showSubtitles(true)

        player.selectSubtitleTrack(6)

        #expect(!player.showsOriginalSubtitles)
        #expect(!player.showsSubtitles)
        #expect(player.subtitleTrack == 6)
        #expect(engine.subtitleTrackChoices == [5, nil])
        #expect(originals.values.isEmpty)
    }

    @Test func choosingSubtitlesDrawnAsPicturesWithOriginalShowsThem() async {
        let (player, _) = await filmPlayer(defaults: original)

        player.selectSubtitleTrack(6)

        #expect(player.showsSubtitles)
        #expect(engine.subtitleTrackChoices == [6])
    }

    @Test func choosingAStyleTurnsOffSubtitlesDrawnAsPicturesUntilOriginalAgain() async throws {
        let (player, _) = await filmPlayer(source: filmWithPictureSubtitles, defaults: original)

        player.chooseCaptionStyle("large")
        #expect(!player.showsOriginalSubtitles)
        #expect(!player.showsSubtitles)
        #expect(player.subtitleTrack == 6)

        player.chooseOriginalSubtitles()
        #expect(!player.showsSubtitles)
        player.showSubtitles(true)
        #expect(engine.subtitleTrackChoices == [nil, 6])
    }

    @Test func choosingAStyleKeepsTextSubtitles() async throws {
        let (player, _) = await filmPlayer(defaults: original)
        player.showSubtitles(true)

        player.chooseCaptionStyle("large")

        #expect(player.showsSubtitles)
    }

    @Test func onShowsTextWithoutOriginal() async {
        let (player, _) = await filmPlayer(source: filmWithPictureSubtitles)

        player.showSubtitles(true)

        #expect(player.showsSubtitles)
        #expect(player.subtitleTrack == 5)
    }

    @Test func offForgetsPicturesWaitingForOriginal() async {
        let (player, _) = await filmPlayer(source: filmWithPictureSubtitles)

        player.showSubtitles(false)
        player.chooseOriginalSubtitles()

        #expect(!player.showsSubtitles)
    }

    @Test func moreOpensQualityWithAutoChosen() async throws {
        let (player, streams) = await filmPlayer()
        player.openMenu("more")
        #expect(try item("quality", in: player.openMenu).detail == "Auto")

        player.choose(try item("quality", in: player.openMenu))
        #expect(player.openMenu?.sections.map(\.header) == ["Quality"])
        #expect(player.menuFocus == "Auto")
        player.choose(try item("8 Mbps", in: player.openMenu))

        await waitUntil { engine.loads.count == 2 }
        #expect(streams.requests.last?.maxBitrate == 8_000_000)
        #expect(player.openMenu == nil)
    }

    @Test func keepsItsControlsWhileHeld() async throws {
        let player = await playingPlayer(controlsTimeout: .milliseconds(30))
        player.showControls()

        player.holdControls(true)
        try await Task.sleep(for: .milliseconds(200))
        #expect(player.showsControls)

        player.holdControls(false)
        await waitUntil { !player.showsControls }
        #expect(!player.showsControls)
    }

    @Test func namesQualitiesAsJellyfinsWebClientDoes() {
        #expect(PlaybackQuality.auto.name == "Auto")
        #expect(PlaybackQuality.original.name == "Original")
        #expect(PlaybackQuality.maxBitrate(120_000_000).name == "120 Mbps")
        #expect(PlaybackQuality.maxBitrate(1_500_000).name == "1.5 Mbps")
        #expect(PlaybackQuality.maxBitrate(720_000).name == "720 kbps")
    }
}

/// A server's streams of `first`: `first` for the first request, then a stream it makes for each
/// after it, with what the request asked for, unless it fails them.
@MainActor
final class Streams {
    let first: PlaybackSource
    let failsAfterFirst: Bool
    private(set) var requests: [PlaybackRequest] = []
    /// The sources the player had the server stop making.
    var stopped: [PlaybackSource] = []
    /// Holds each request after the first until `releaseRequests()`.
    var holdsRequests = false
    private var held: [CheckedContinuation<Void, Never>] = []

    init(first: PlaybackSource, failsAfterFirst: Bool) {
        self.first = first
        self.failsAfterFirst = failsAfterFirst
    }

    func releaseRequests() {
        held.forEach { $0.resume() }
        held = []
    }

    func source(for request: PlaybackRequest) async throws -> PlaybackSource {
        requests.append(request)
        guard requests.count > 1 else { return first }
        if holdsRequests { await withCheckedContinuation { held.append($0) } }
        if failsAfterFirst { throw JellyfinError.unreachable }
        let subtitles: MediaTrack.ID? = switch request.subtitles {
        case .track(let id): id
        case .off, nil: nil
        }
        return PlaybackSource(
            url: URL(string: "https://media.test/master-\(requests.count).m3u8")!,
            versionID: first.versionID,
            playSessionID: "session-\(requests.count)",
            method: request.maxBitrate == nil && request.audioTrack != 7 && subtitles != 1 ? .directPlay : .transcode,
            audioTracks: first.audioTracks,
            subtitleTracks: first.subtitleTracks,
            audioTrack: request.audioTrack,
            subtitleTrack: subtitles,
            bitrate: first.bitrate
        )
    }
}

/// What a player told its server, in order.
@MainActor
final class Reports {
    var started: [(source: PlaybackSource, position: Duration)] = []
    var progress: [(source: PlaybackSource, position: Duration, isPaused: Bool)] = []
    var stopped: [(source: PlaybackSource, position: Duration)] = []
}

/// Reports that each take a while to reach the server, the first longest, as over a slow network.
@MainActor
final class SlowReports {
    private(set) var received: [String] = []
    private var sent = 0

    func record(_ report: String) async {
        sent += 1
        try? await Task.sleep(for: .milliseconds(sent == 1 ? 50 : 10))
        received.append(report)
    }
}

/// The system's caption styles, as a test sets them: Classic, Large Text (half as big again) and
/// Transparent Background, which is chosen.
final class FakeCaptionStyles: @unchecked Sendable {
    var chosen: CaptionStyleOption.ID? = "transparent"

    var styles: CaptionStyles {
        CaptionStyles(
            options: {
                [
                    CaptionStyleOption(id: "classic", name: "Classic"),
                    CaptionStyleOption(id: "large", name: "Large Text"),
                    CaptionStyleOption(id: "transparent", name: "Transparent Background"),
                ]
            },
            chosen: { self.chosen },
            choose: { self.chosen = $0 },
            appearance: { CaptionStyle(sizeScale: $0 == "large" ? 1.5 : 1) }
        )
    }
}

/// Counts the changes to what shows the time, as a view showing it would see them.
@MainActor
final class TimeChanges {
    private(set) var count = 0

    func watch(_ player: PlayerViewModel) {
        withObservationTracking {
            _ = player.elapsedLabel
            _ = player.remainingLabel
            _ = player.progress
            _ = player.playbackProgress
        } onChange: { [weak self] in
            MainActor.assumeIsolated { self?.count += 1 }
        }
    }
}

/// What a test's closure was called with, in order.
final class Recorded<Value>: @unchecked Sendable {
    var values: [Value] = []
}
