import Foundation
import Observation
import PortfolioShared
import PortfolioSharedPlaybackEngine
import SwiftUI

/// One thing playing: it finds where the media plays from, opens it in its engine and plays it, and
/// says what's happening. Closing it stops the engine. Each player has an engine of its own. It tells
/// the server when playback starts, where it is every `progressInterval` and whenever it pauses or
/// plays, and where it stopped.
///
/// Its controls are a transport bar: they show on any press, and hide by themselves after
/// `controlsTimeout` while it plays, staying while it's paused or held. Playing and pausing, scrubbing
/// while paused (picking a spot, then playing from it), clicking Left and Right to skip or move the spot,
/// holding one to set the needle moving by itself, and choosing the audio track, the subtitles and the
/// quality go through here. A choice the engine can make in the stream playing, it makes; one that
/// needs another stream asks the server for it and plays it from where playback is, then has the server
/// stop making the stream it left.
///
/// The load belongs to the view model, not to the view's task: SwiftUI can cancel and restart a view's
/// task while the server is still answering.
@MainActor
@Observable
public final class PlayerViewModel: Identifiable {
    public let id = UUID()
    /// What's playing, for what's said about it.
    public let title: String
    /// What the title belongs to, shown small above it: a show and which episode, for one.
    public let subtitle: String?

    @ObservationIgnored private let engine: (any PlaybackEngine)?
    @ObservationIgnored private let source: (PlaybackRequest) async throws -> PlaybackSource
    @ObservationIgnored private let stopTranscoding: ((PlaybackSource) async -> Void)?
    @ObservationIgnored private let captionStyles: CaptionStyles
    @ObservationIgnored private let preferences: UserDefaults
    /// What it starts on, from the profile's Settings.
    @ObservationIgnored private let playbackDefaults: PlaybackDefaults
    @ObservationIgnored private let rememberOriginalSubtitles: ((Bool) -> Void)?
    /// The system's caption styles, and how each looks, once asked for.
    @ObservationIgnored private lazy var captionStyleOptions = captionStyles.options().map { ($0, captionStyles.appearance($0.id)) }
    @ObservationIgnored private let startPosition: () async -> Duration
    @ObservationIgnored private let describe: (any Error) -> String
    @ObservationIgnored private let reportStarted: ((PlaybackSource, Duration) async -> Void)?
    @ObservationIgnored private let reportProgress: ((PlaybackSource, Duration, Bool) async -> Void)?
    @ObservationIgnored private let reportStopped: ((PlaybackSource, Duration) async -> Void)?
    @ObservationIgnored private let progressInterval: Duration
    /// The report sent last, which the next waits for.
    @ObservationIgnored private var lastReport: Task<Void, Never>?
    /// Reports where playback is every `progressInterval`, from when it starts until it closes.
    @ObservationIgnored private var reportingProgress: Task<Void, Never>?
    @ObservationIgnored private var loading: Task<Void, Never>?
    /// Moving to another stream, for a choice the stream playing can't give.
    @ObservationIgnored private var changingStream: Task<Void, Never>?
    /// What's playing, once it has started, until it stops: the stream, and the tracks playing in it.
    private var playing: PlaybackSource?
    /// The subtitles shown last, which turning them on shows again.
    private var lastSubtitleTrack: MediaTrack.ID?
    @ObservationIgnored private var isClosed = false
    @ObservationIgnored private let controlsTimeout: Duration
    @ObservationIgnored private var hidingControls: Task<Void, Never>?

    /// Whether the transport bar shows.
    public private(set) var showsControls = false
    /// Whether something keeps the controls up while it plays, such as focus on their menus.
    @ObservationIgnored private var holdsControls = false
    /// How fast a stream it asks for.
    public private(set) var quality = PlaybackQuality.auto
    /// Whether it narrows the audio's range, so loud scenes are quieter. It's remembered for the next
    /// player.
    public private(set) var reducesLoudSounds: Bool
    /// Whether Style is Original: subtitles as the file has them, rather than in a system caption style.
    /// Subtitles drawn as pictures (Blu-ray, DVD, DVB), which nothing can restyle, show only then. It's
    /// kept for the item (`rememberOriginalSubtitles`).
    public private(set) var showsOriginalSubtitles: Bool
    /// Subtitles drawn as pictures chosen, or showing, while Style wasn't Original: off, and On shows
    /// them once it is.
    private var heldPictureTrack: MediaTrack.ID?
    /// The system caption style chosen.
    private var chosenCaptionStyle: CaptionStyleOption.ID?
    /// The menu open, then each submenu opened from it.
    private var openMenuIDs: [PlayerMenu.ID] = []
    /// The menu whose button opened what's open. Kept on its own rather than worked out from
    /// `openMenuIDs`: the player follows it, and was drawn again whenever a submenu opened, just as the
    /// menu's motion began.
    public private(set) var openMenuRoot: PlayerMenu.ID?
    /// The item in the open menu focus goes to: the first as a menu opens, the one chosen as a submenu
    /// opens, and the one a submenu was opened from as it closes.
    public private(set) var menuFocus: PlayerMenu.Item.ID?
    /// Where scrubbing would take playback, while scrubbing.
    public private(set) var scrubPosition: Duration?
    /// The needle moving along the bar by itself, as holding Left or Right sets it going, until it's
    /// stopped or reaches an end.
    public private(set) var drive: Drive?
    @ObservationIgnored private var driving: Task<Void, Never>?
    /// The skip just made, shown beside the elapsed time until a moment after playback gets there.
    public private(set) var skipHint: SkipHint?
    @ObservationIgnored private var clearingSkipHint: Task<Void, Never>?
    /// The server's pictures of the video at a steady interval, once it's said, if it has any.
    public private(set) var trickplay: Trickplay?
    /// The server's picture of the spot, while scrubbing, once it's loaded: the one before until then.
    public private(set) var scrubPreview: CGImage?
    /// Which of the server's pictures `scrubPreview` is, or is loading.
    @ObservationIgnored private var previewIndex: Int?
    @ObservationIgnored private var loadingPreview: Task<Void, Never>?
    @ObservationIgnored private let findTrickplay: ((PlaybackSource) async -> Trickplay?)?
    @ObservationIgnored private let pipeline: ImagePipeline
    /// Whether it's been paused: what was asked for, which the engine says a moment later, and not while
    /// it seeks.
    public private(set) var isPaused = false
    /// Whether it's been paused, by Select or Play/Pause or by the app going to the background, and
    /// nothing done since: Menu then leaves playback, rather than playing on (`resume()`).
    public private(set) var isPausedUntouched = false
    /// Where a seek is taking playback, until it's there.
    private var seekTarget: Duration?
    /// Where the engine says playback is, as the controls show it: kept as the media plays, and changed
    /// only when what they show would change (`shows(_:otherwiseThan:in:)`), so only what shows the time
    /// is drawn again, and only then. The engine's own time changes about 10 times a second, and every
    /// view reading it was drawn again with it.
    private var shownTime = Duration.zero
    /// How long the media is, once the engine has said: an engine opening another stream says zero
    /// until it knows, and the bar went back to the start meanwhile.
    private var knownDuration = Duration.zero
    /// Keeps `shownTime` as the media plays, from `start()` until it closes.
    @ObservationIgnored private var followingPlayback: Task<Void, Never>?
    /// Why it can't play, found before the engine had anything to play.
    private var failure: String?
    /// Whether it's still starting: from `start()` until it's asked to play.
    private var isStarting = false

    /// - Parameters:
    ///   - makeEngine: the engine to play it in.
    ///   - position: finds where to start in it, once `source` has found where it plays from.
    ///   - source: finds where it plays from, as a request asks, such as by asking its server.
    ///   - describe: why `source` failed, in words.
    ///   - stopTranscoding: has the server stop making a stream it has moved on from.
    ///   - reportStarted: tells the server playback started from a source, at a position.
    ///   - reportProgress: tells it where playback is, and whether it's paused.
    ///   - reportStopped: tells it where playback stopped.
    ///   - controlsTimeout: how long the controls stay while it plays and nothing is pressed.
    ///   - progressInterval: how often it reports where playback is.
    ///   - captionStyles: the caption styles to choose from.
    ///   - preferences: where it remembers whether to reduce loud sounds.
    ///   - playbackDefaults: the most Auto streams at, and the languages it starts in, from Settings, and
    ///     whether Style starts on Original.
    ///   - rememberOriginalSubtitles: keeps whether Style is Original for the item, as it changes.
    ///   - trickplay: finds the server's pictures of what a source plays at a steady interval, to show
    ///     where scrubbing would take it, once it plays.
    ///   - pipeline: loads those pictures.
    init(
        title: String,
        subtitle: String? = nil,
        makeEngine: () throws -> any PlaybackEngine,
        startingAt position: @escaping () async -> Duration = { .zero },
        source: @escaping (PlaybackRequest) async throws -> PlaybackSource,
        describe: @escaping (any Error) -> String,
        stopTranscoding: ((PlaybackSource) async -> Void)? = nil,
        reportStarted: ((PlaybackSource, Duration) async -> Void)? = nil,
        reportProgress: ((PlaybackSource, Duration, Bool) async -> Void)? = nil,
        reportStopped: ((PlaybackSource, Duration) async -> Void)? = nil,
        controlsTimeout: Duration = PlayerViewModel.controlsTimeout,
        progressInterval: Duration = PlayerViewModel.progressInterval,
        captionStyles: CaptionStyles = .system,
        preferences: UserDefaults = .standard,
        playbackDefaults: PlaybackDefaults = PlaybackDefaults(),
        rememberOriginalSubtitles: ((Bool) -> Void)? = nil,
        trickplay: ((PlaybackSource) async -> Trickplay?)? = nil,
        pipeline: ImagePipeline = .shared
    ) {
        self.findTrickplay = trickplay
        self.pipeline = pipeline
        self.title = title
        self.subtitle = subtitle
        self.controlsTimeout = controlsTimeout
        self.progressInterval = progressInterval
        self.source = source
        self.describe = describe
        self.stopTranscoding = stopTranscoding
        self.reportStarted = reportStarted
        self.reportProgress = reportProgress
        self.reportStopped = reportStopped
        self.captionStyles = captionStyles
        self.preferences = preferences
        self.playbackDefaults = playbackDefaults
        self.rememberOriginalSubtitles = rememberOriginalSubtitles
        startPosition = position
        reducesLoudSounds = preferences.bool(forKey: Self.reducesLoudSoundsKey)
        showsOriginalSubtitles = playbackDefaults.showsOriginalSubtitles
        chosenCaptionStyle = captionStyles.chosen()
        do {
            engine = try makeEngine()
        } catch {
            engine = nil
            failure = "Playback isn't available right now."
        }
        engine?.setReducesLoudSounds(reducesLoudSounds)
    }

    /// Where it remembers whether to reduce loud sounds.
    static let reducesLoudSoundsKey = "playback.reducesLoudSounds"
    /// Original's place among the caption styles.
    static let originalStyleID = "original"

    /// Plays `source` as it is from the beginning, such as a test video, with nothing to ask a server
    /// first.
    public convenience init(title: String, source: PlaybackSource, makeEngine: () throws -> any PlaybackEngine) {
        self.init(title: title, makeEngine: makeEngine, source: { _ in source }, describe: { _ in "Couldn't open \(title)." })
    }

    /// What it's doing.
    public var status: PlaybackStatus {
        if let failure { return .failed(failure) }
        return engine?.status ?? .idle
    }

    /// Whether to show that it's waiting: until it plays, and whenever it runs short. An engine can say
    /// it's paused before it plays, as AetherEngine does while the TV switches to the media's frame rate
    /// and dynamic range, which takes a few seconds.
    public var isWaiting: Bool {
        switch status {
        case .idle, .loading, .buffering: true
        case .paused: isStarting
        case .playing, .ended, .failed: false
        }
    }

    /// Whether it has played to the end.
    public var hasEnded: Bool {
        status == .ended
    }

    /// Why it can't play, in words, or nil while it can.
    public var message: String? {
        if let failure { return failure }
        guard case .failed = status else { return nil }
        return "Couldn't play \(title)."
    }

    /// What it's doing, in a word, for accessibility.
    public var statusName: String {
        switch status {
        case .idle: "idle"
        case .loading: "loading"
        case .playing: "playing"
        case .paused: "paused"
        case .buffering: "buffering"
        case .ended: "ended"
        case .failed: "failed"
        }
    }

    /// The picture.
    public var surface: AnyView {
        engine?.surface ?? AnyView(EmptyView())
    }

    /// The subtitles showing, to lay over the picture.
    public var subtitles: AnyView {
        engine?.subtitles ?? AnyView(EmptyView())
    }

    /// Finds where it plays from, opens it there and plays it. It starts once; asking again does
    /// nothing.
    public func start() {
        guard loading == nil, let engine else { return }
        isStarting = true
        followPlayback()
        var playbackDefaults = playbackDefaults
        playbackDefaults.showsOriginalSubtitles = showsOriginalSubtitles
        loading = Task { [weak self, source, stopTranscoding, startPosition, reportStarted, playbackDefaults] in
            // Failing, too, it's no longer starting.
            defer { self?.isStarting = false }
            do {
                let first = try await source(playbackDefaults.startingRequest)
                let found = try await Self.startingTracks(in: first, playbackDefaults, source: source, stopTranscoding: stopTranscoding)
                let position = await startPosition()
                try Task.checkCancellation()
                try await engine.load(found, startingAt: position)
                engine.play()
                guard let self else { return }
                isStarting = false
                playing = found
                lastSubtitleTrack = found.subtitleTrack
                // Pictures the server would show are chosen, but wait for Original.
                if found.subtitleTrack == nil, let pictures = first.showingSubtitleTrack, !pictures.isText {
                    heldPictureTrack = pictures.id
                    lastSubtitleTrack = pictures.id
                }
                if let reportStarted { send { await reportStarted(found, position) } }
                startReportingProgress()
                if let findTrickplay {
                    trickplay = await findTrickplay(found)
                    showPreview()
                }
            } catch is CancellationError {
                // Closed meanwhile.
            } catch {
                // The engine says why it failed itself; anything before it didn't get that far.
                if case .failed = engine.status { return }
                self?.fail(with: error)
            }
        }
    }

    /// `found` on the tracks Settings starts on, in place of the server's picks, with picture subtitles
    /// off unless Style is Original: changed in place where the file plays as it is with them in it, else
    /// asked of the server again before anything plays, the server stopping the stream it made first.
    private static func startingTracks(
        in found: PlaybackSource,
        _ defaults: PlaybackDefaults,
        source: (PlaybackRequest) async throws -> PlaybackSource,
        stopTranscoding: ((PlaybackSource) async -> Void)?
    ) async throws -> PlaybackSource {
        let audio = defaults.audioTrack(in: found)
        let subtitles = defaults.subtitles(in: found)
        guard audio != nil || subtitles != nil else { return found }
        let subtitleTrack: MediaTrack.ID? = switch subtitles {
        case .track(let id): id
        case .off: nil
        case nil: found.subtitleTrack
        }
        // The server draws some subtitles into the picture: adding or taking them away takes a stream.
        let needsStream = found.method == .transcode
            || found.audioTracks.contains { $0.id == audio && $0.delivery == .transcoded }
            || (subtitles != nil && [subtitleTrack, found.subtitleTrack].contains { id in
                found.subtitleTracks.contains { $0.id == id && $0.delivery == .transcoded }
            })
        guard needsStream else {
            var changed = found
            if let audio { changed.audioTrack = audio }
            changed.subtitleTrack = subtitleTrack
            return changed
        }
        var request = defaults.startingRequest
        request.versionID = found.versionID
        request.audioTrack = audio ?? found.audioTrack
        request.subtitles = subtitleTrack.map(PlaybackRequest.Subtitles.track) ?? .off
        let again = try await source(request)
        if found.method == .transcode { await stopTranscoding?(found) }
        return again
    }

    // MARK: Controls

    /// Where playback is, as the controls show it: where scrubbing would take it, while scrubbing, and
    /// where a seek is taking it.
    public var position: Duration {
        scrubPosition ?? shownPlaybackPosition
    }

    /// Where playback is as the controls show it, or where a seek is taking it, whatever spot scrubbing
    /// has picked.
    private var shownPlaybackPosition: Duration {
        seekTarget ?? shownTime
    }

    /// Where playback is exactly, or where a seek is taking it, whatever spot scrubbing has picked: what
    /// the server hears, and where another stream starts.
    private var playbackPosition: Duration {
        seekTarget ?? engine?.currentTime ?? .zero
    }

    /// Whether the controls would show `time` otherwise than `shown`, in media `duration` long: in
    /// another second, as the times show it, or with the bar at least a `barSteps`th of the media further
    /// along, which moves the bar of short media smoothly.
    nonisolated static func shows(_ time: Duration, otherwiseThan shown: Duration, in duration: Duration) -> Bool {
        time.components.seconds != shown.components.seconds
            || duration > .zero && abs((time - shown) / duration) * Double(barSteps) >= 1
    }

    /// How many steps the bar moves in: more than a TV's bar has points.
    nonisolated static let barSteps = 2_000

    /// Keeps `shownTime` as the engine plays.
    private func followPlayback() {
        let times = Observations { @MainActor [weak self] in
            self?.engine?.currentTime
        }
        followingPlayback = Task { [weak self] in
            for await time in times {
                guard let self, let time else { return }
                if let length = engine?.duration, length > .zero, length != knownDuration { knownDuration = length }
                if Self.shows(time, otherwiseThan: shownTime, in: duration) { shownTime = time }
            }
        }
    }

    /// The seek is over: the controls follow the engine again, from where it is now rather than once it
    /// next moves on.
    private func finishSeeking() {
        seekTarget = nil
        if let time = engine?.currentTime, time != shownTime { shownTime = time }
    }

    /// How long the media is: zero until it's known, and as it was known while another stream opens.
    public var duration: Duration {
        guard let length = engine?.duration, length > .zero else { return knownDuration }
        return length
    }

    /// How far through the media `position` is, from 0 to 1.
    public var progress: Double {
        guard duration > .zero else { return 0 }
        return min(1, max(0, position / duration))
    }

    /// How far through the media playback is, from 0 to 1, whatever spot scrubbing has picked.
    public var playbackProgress: Double {
        guard duration > .zero else { return 0 }
        return min(1, max(0, shownPlaybackPosition / duration))
    }

    /// "00:08" or "12:34", then "1:02:03" from an hour in, as the system's player shows it, however long
    /// the media.
    public var elapsedLabel: String {
        Self.label(for: position, hours: position >= .seconds(3600))
    }

    /// "-1:47:26": what's left after `position`.
    public var remainingLabel: String {
        "-" + Self.label(for: max(.zero, duration - position), hours: duration >= .seconds(3600))
    }

    public var isScrubbing: Bool {
        scrubPosition != nil
    }

    /// Shows the controls, and counts down to hiding them again while it plays.
    public func showControls() {
        if !showsControls { showsControls = true }
        scheduleHidingControls()
    }

    public func hideControls() {
        hidingControls?.cancel()
        if showsControls { showsControls = false }
    }

    /// Keeps the controls up while `held`, such as while focus is on their menus, then counts down to
    /// hiding them again.
    public func holdControls(_ held: Bool) {
        if held { isPausedUntouched = false }
        guard held != holdsControls else { return }
        holdsControls = held
        if showsControls { scheduleHidingControls() }
    }

    /// Select or Play/Pause: plays from the spot picked while scrubbing, or else pauses or plays.
    public func togglePlayPause() {
        guard let engine else { return }
        if let target = scrubPosition {
            stopDriving()
            moveSpot(to: nil)
            isPaused = false
            seek(to: target)
        } else if isPaused {
            isPaused = false
            engine.play()
        } else {
            isPaused = true
            engine.pause()
        }
        isPausedUntouched = isPaused
        showControls()
        sendProgress()
    }

    /// Moves playback to `target`, then plays or stays paused as it was asked: an engine can come out of
    /// a seek playing. Gives the seek, which ends once the engine is there.
    @discardableResult
    private func seek(to target: Duration) -> Task<Void, Never> {
        guard let engine else { return Task {} }
        seekTarget = target
        return Task { [weak self] in
            await engine.seek(to: target)
            guard let self, self.seekTarget == target else { return }
            self.finishSeeking()
            if self.isPaused { engine.pause() } else { engine.play() }
        }
    }

    /// Starts picking a spot to play from, while paused. A swipe starting does it, so it stops the
    /// needle moving by itself: the finger takes it from there.
    public func beginScrubbing() {
        guard isPaused else { return }
        isPausedUntouched = false
        stopDriving()
        if scrubPosition == nil { moveSpot(to: position) }
        showControls()
    }

    /// Moves the spot to `fraction` of the way through the media, as the bar's needle moves there. At
    /// `playbackProgress` it's exactly where playback is.
    public func scrub(to fraction: Double) {
        guard isScrubbing, duration > .zero else { return }
        moveSpot(to: fraction == playbackProgress ? playbackPosition : duration * min(1, max(0, fraction)))
        showControls()
    }

    /// Clicking Left or Right, as the system player takes it. With the needle moving by itself, it goes
    /// faster that way, or slower the other (`Drive.stepped(_:)`). Scrubbing, or paused with the
    /// controls up, it moves the spot `scrubStep` that way, starting to scrub. Otherwise it skips
    /// playback by Settings' Skip Back or Skip Forward, showing which beside the time
    /// (`skipHint`), and shows the controls.
    public func click(_ direction: Direction) {
        guard engine != nil, duration > .zero else { return }
        isPausedUntouched = false
        if let drive {
            self.drive = drive.stepped(direction)
            showControls()
        } else if isScrubbing || isPaused && showsControls {
            beginScrubbing()
            guard let spot = scrubPosition else { return }
            moveSpot(to: min(max(spot + Self.scrubStep * direction.sign, .zero), duration))
            showSkip(direction, by: Self.scrubStep, until: nil)
        } else {
            skip(direction)
        }
    }

    /// Holding Left or Right, as the system player takes it: playback pauses, and the needle sets off
    /// from where it is that way, at the slowest speed. It goes on after the click lets go, until
    /// Select or Play/Pause plays from it, a swipe takes it over, it reaches an end, or Menu plays from
    /// where playback paused (`resume()`). Held again while it moves, it's as a click.
    public func hold(_ direction: Direction) {
        guard let engine, duration > .zero else { return }
        isPausedUntouched = false
        guard drive == nil else {
            click(direction)
            return
        }
        if !isPaused {
            isPaused = true
            engine.pause()
            sendProgress()
        }
        if scrubPosition == nil { moveSpot(to: playbackPosition) }
        drive = Drive(rate: Drive.rates[0] * direction.sign)
        showControls()
        startDriving()
    }

    /// Skips playback by Settings' Skip Back or Skip Forward, within the media, and shows which until
    /// `skipHintDelay` after playback gets there, as the system player does.
    private func skip(_ direction: Direction) {
        let interval = direction == .forward ? playbackDefaults.skipForward : playbackDefaults.skipBack
        let landing = seek(to: min(max(playbackPosition + interval * direction.sign, .zero), duration))
        showControls()
        showSkip(direction, by: interval, until: landing)
    }

    /// Shows a skip `direction` by `interval` beside the time, until `skipHintDelay` after `landing`
    /// ends, or after now without one.
    private func showSkip(_ direction: Direction, by interval: Duration, until landing: Task<Void, Never>?) {
        skipHint = SkipHint(direction: direction, seconds: Int(interval.components.seconds))
        clearingSkipHint?.cancel()
        clearingSkipHint = Task { [weak self] in
            await landing?.value
            try? await Task.sleep(for: Self.skipHintDelay)
            guard !Task.isCancelled else { return }
            self?.skipHint = nil
        }
    }

    /// Menu while scrubbing: the spot goes back where playback paused, the needle stops, and the
    /// controls are as they are paused, the title and menu buttons back. Menu again plays on.
    public func cancelScrubbing() {
        guard isScrubbing else { return }
        stopDriving()
        moveSpot(to: nil)
        showControls()
    }

    /// Menu while paused: plays from where playback paused, leaving any spot picked but not played from,
    /// and the needle moving by itself.
    public func resume() {
        guard let engine, isPaused else { return }
        stopDriving()
        moveSpot(to: nil)
        isPaused = false
        isPausedUntouched = false
        engine.play()
        showControls()
        sendProgress()
    }

    /// The app went to the background, as when the user switches to another: it pauses, so it's
    /// waiting where it was on the way back, with its controls up. AetherEngine lets go of the video
    /// there on tvOS, and opens it again on the way back.
    public func enteredBackground() {
        guard let engine, !isPaused, duration > .zero else { return }
        isPaused = true
        isPausedUntouched = true
        engine.pause()
        showControls()
        sendProgress()
    }

    /// Moves the spot as `drive` says, as often as AVKit's needle moves, until it's stopped, or reaches
    /// an end, where it stops.
    private func startDriving() {
        driving?.cancel()
        driving = Task { [weak self] in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.driveInterval)
                let now = ContinuousClock.now
                guard !Task.isCancelled, let self, let drive = self.drive, let spot = self.scrubPosition else { return }
                let moved = min(max(spot + (now - last) * drive.rate, .zero), self.duration)
                last = now
                self.moveSpot(to: moved)
                if moved == .zero || moved == self.duration {
                    self.drive = nil
                    return
                }
            }
        }
    }

    private func stopDriving() {
        driving?.cancel()
        driving = nil
        if drive != nil { drive = nil }
    }

    /// Moves the spot scrubbing picks, or puts it away, and shows the server's picture of it.
    private func moveSpot(to spot: Duration?) {
        scrubPosition = spot
        showPreview()
    }

    /// Shows the server's picture of the spot, while scrubbing: at once if its tile is in memory, else
    /// once it's loaded, unless the spot has moved on to another meanwhile, the one before staying
    /// until then. Tiles are loaded whole, so the pictures near one already loaded show at once.
    private func showPreview() {
        guard let trickplay, let spot = scrubPosition, let picture = trickplay.picture(at: spot) else {
            loadingPreview?.cancel()
            previewIndex = nil
            if scrubPreview != nil { scrubPreview = nil }
            return
        }
        guard picture.index != previewIndex else { return }
        previewIndex = picture.index
        loadingPreview?.cancel()
        if let tile = pipeline.cachedImage(for: picture.tileURL) {
            scrubPreview = tile.cropping(to: picture.rect)
            return
        }
        loadingPreview = Task { [weak self, pipeline] in
            let tile = try? await pipeline.image(for: picture.tileURL, httpHeaders: trickplay.httpHeaders, priority: .high)
            guard let self, let tile, !Task.isCancelled, previewIndex == picture.index else { return }
            scrubPreview = tile.cropping(to: picture.rect)
        }
    }

    /// Hides the controls after `controlsTimeout`, unless it's paused, scrubbing or they're held.
    private func scheduleHidingControls() {
        hidingControls?.cancel()
        guard !isPaused, !isScrubbing, !holdsControls else { return }
        hidingControls = Task { [weak self, controlsTimeout] in
            try? await Task.sleep(for: controlsTimeout)
            guard !Task.isCancelled else { return }
            self?.hideControls()
        }
    }

    private static func label(for duration: Duration, hours: Bool) -> String {
        duration.formatted(.time(pattern: hours ? .hourMinuteSecond : .minuteSecond(padMinuteToLength: 2)))
    }

    /// How long the controls stay while it plays and nothing is pressed.
    public nonisolated static let controlsTimeout = Duration.seconds(5)
    /// How far a click moves the spot while scrubbing, whatever Settings' skips: AVKit's
    /// (`skipToNextScrubbingFrame`).
    nonisolated static let scrubStep = Duration.seconds(10)
    /// How long a skip shows once playback gets there: AVKit's (`clearHintAfterDelay`).
    nonisolated static let skipHintDelay = Duration.milliseconds(300)
    /// How often the needle moves by itself: AVKit's timer, at 48 Hz.
    nonisolated static let driveInterval = Duration.seconds(1.0 / 48)

    /// Which way a click, a hold or the needle goes: Left or Right.
    public enum Direction: Hashable, Sendable {
        case back
        case forward

        var sign: Double {
            self == .forward ? 1 : -1
        }

        /// The side of the time that shows it.
        var side: HorizontalEdge {
            self == .forward ? .trailing : .leading
        }
    }

    /// A skip just made, as the controls show it: which way, and how far, in seconds.
    public struct SkipHint: Hashable, Sendable {
        public let direction: Direction
        public let seconds: Int
    }

    /// What shows beside the elapsed time, as the system player shows it: the needle moving by itself,
    /// which way, with its speed from the second; else a skip just made, how far; else a pause symbol
    /// while paused, unless a finger is moving the spot (`isInteracting`). Going back, it's before the
    /// time, and on, after it.
    public func timeBadge(isInteracting: Bool) -> TimeBadge? {
        if let drive {
            return TimeBadge(
                kind: .drive,
                symbol: drive.direction == .forward ? "forward.circle" : "backward.circle",
                number: drive.speed > 1 ? "\(drive.speed)" : nil,
                side: drive.direction.side
            )
        }
        if let skipHint {
            let name = skipHint.direction == .forward ? "goforward" : "gobackward"
            let drawn = Self.skipSymbolSeconds.contains(skipHint.seconds)
            return TimeBadge(
                kind: .skip,
                symbol: drawn ? "\(name).\(skipHint.seconds)" : name,
                number: nil,
                side: skipHint.direction.side
            )
        }
        guard isPaused, !isInteracting else { return nil }
        return TimeBadge(kind: .pause, symbol: "pause.circle", number: nil, side: .trailing)
    }

    /// What's beside the time: a symbol, and a number after it, on a side of the time.
    public struct TimeBadge: Hashable, Sendable {
        public let kind: Kind
        public let symbol: String
        public let number: String?
        public let side: HorizontalEdge

        public enum Kind: Hashable, Sendable {
            case pause
            /// A skip just made: an arrow round a circle, which reaches above it.
            case skip
            /// The needle moving by itself.
            case drive
        }
    }

    /// The skips SF Symbols draws with their seconds in them.
    nonisolated static let skipSymbolSeconds: Set = [5, 10, 15, 30, 45, 60, 75, 90]

    /// The needle moving by itself: how fast, in seconds of the media a second, back when negative.
    public struct Drive: Hashable, Sendable {
        public let rate: Double

        /// The speeds, either way: AVKit's (`AVScrubbingController.defaultScrubbingRates`), 8 to 96.
        nonisolated static let rates: [Double] = [8, 24, 48, 96]

        public var direction: Direction {
            rate < 0 ? .back : .forward
        }

        /// Which speed it's at, from 1 for the slowest. The system player shows it from 2.
        public var speed: Int {
            (Self.rates.firstIndex(of: abs(rate)) ?? 0) + 1
        }

        /// The next speed `direction`: faster that way, or slower the other, past the slowest to the
        /// slowest the other way, as AVKit's `advanceToHigherRate` and `advanceToLowerRate` go. It
        /// stays at the fastest.
        func stepped(_ direction: Direction) -> Drive {
            let all = Self.rates.reversed().map { -$0 } + Self.rates
            guard let index = all.firstIndex(of: rate) else { return self }
            let next = min(max(index + (direction == .forward ? 1 : -1), 0), all.count - 1)
            return Drive(rate: all[next])
        }
    }

    // MARK: Tracks and quality

    /// The audio tracks to choose from, once it plays.
    public var audioTracks: [MediaTrack] {
        playing?.audioTracks ?? []
    }

    /// The audio track playing.
    public var audioTrack: MediaTrack.ID? {
        playing?.audioTrack
    }

    /// The subtitles to choose from, once it plays.
    public var subtitleTracks: [MediaTrack] {
        playing?.subtitleTracks ?? []
    }

    /// Whether subtitles show.
    public var showsSubtitles: Bool {
        playing?.subtitleTrack != nil
    }

    /// The subtitles chosen: those showing, else pictures waiting for Original, else those On shows.
    public var subtitleTrack: MediaTrack.ID? {
        playing?.subtitleTrack ?? heldPictureTrack ?? subtitlesOnShows
    }

    /// What On shows: those shown last, else the first in Settings' subtitle language, else the ones the
    /// media marks to use, else the first. Text, unless Style is Original or there are only pictures.
    private var subtitlesOnShows: MediaTrack.ID? {
        let text = subtitleTracks.filter(\.isText)
        let tracks = showsOriginalSubtitles || text.isEmpty ? subtitleTracks : text
        if let last = lastSubtitleTrack, tracks.contains(where: { $0.id == last }) { return last }
        if let code = playbackDefaults.subtitleLanguage,
            let inLanguage = tracks.first(where: { !$0.isForced && $0.language?.caseInsensitiveCompare(code) == .orderedSame }) {
            return inLanguage.id
        }
        return (tracks.first { $0.isDefault && !$0.isForced } ?? tracks.first)?.id
    }

    /// The name of `subtitleTrack`.
    public var subtitleTrackTitle: String? {
        subtitleTracks.first { $0.id == subtitleTrack }?.title
    }

    /// The qualities to choose from: Auto, Original, then the bitrates below the file's.
    public var qualities: [PlaybackQuality] {
        PlaybackQuality.choices(forBitrate: playing?.bitrate)
    }

    /// Plays audio track `id` from where playback is.
    public func selectAudioTrack(_ id: MediaTrack.ID) {
        guard let playing, playing.audioTrack != id, let track = playing.audioTracks.first(where: { $0.id == id }) else { return }
        if playing.method == .directPlay, track.delivery == .inStream {
            engine?.selectAudioTrack(track)
            self.playing?.audioTrack = id
            sendProgress()
        } else {
            changeStream { $0.audioTrack = id }
        }
    }

    /// Turns subtitles on, or off.
    public func showSubtitles(_ shows: Bool) {
        showSubtitleTrack(shows ? subtitlesOnShows : nil)
    }

    /// Shows subtitles `id`, turning them on.
    public func selectSubtitleTrack(_ id: MediaTrack.ID) {
        showSubtitleTrack(id)
    }

    /// Asks for streams as `quality` says, from where playback is. Original while the file plays as it is
    /// already changes nothing but what later streams are asked for.
    public func selectQuality(_ quality: PlaybackQuality) {
        guard let playing, quality != self.quality else { return }
        if quality == .original, playing.method == .directPlay {
            self.quality = quality
            return
        }
        changeStream(to: quality) { _ in }
    }

    /// Shows subtitles `id`, or none. Pictures show only while Style is Original: otherwise they're chosen
    /// but stay off, Style as it was, and whatever showed goes.
    private func showSubtitleTrack(_ id: MediaTrack.ID?) {
        guard let playing else { return }
        if let track = playing.subtitleTracks.first(where: { $0.id == id }), !track.isText, !showsOriginalSubtitles {
            heldPictureTrack = track.id
            lastSubtitleTrack = track.id
            applySubtitleTrack(nil)
        } else {
            heldPictureTrack = nil
            applySubtitleTrack(id)
        }
    }

    /// Shows subtitles `id`, or none. The server draws some into the picture, which takes a stream made
    /// with them, and a stream made without them to take them away.
    private func applySubtitleTrack(_ id: MediaTrack.ID?) {
        guard let playing, playing.subtitleTrack != id else { return }
        let track = id.flatMap { id in playing.subtitleTracks.first { $0.id == id } }
        if let id { lastSubtitleTrack = id }
        if track?.delivery == .transcoded || playing.showingSubtitleTrack?.delivery == .transcoded {
            changeStream { $0.subtitles = id.map(PlaybackRequest.Subtitles.track) ?? .off }
        } else {
            engine?.selectSubtitleTrack(track)
            self.playing?.subtitleTrack = id
            sendProgress()
        }
    }

    /// Asks for a stream like the one playing, but at `quality` and as `change` says, then plays it from
    /// where playback has got to, paused if it was, and has the server stop making the one it left. A
    /// newer change takes the place of one still on its way. If the server can't send it, the stream
    /// playing plays on, and if it's the file playing already, that plays on without opening it again.
    private func changeStream(to quality: PlaybackQuality? = nil, _ change: (inout PlaybackRequest) -> Void) {
        guard let playing, let engine else { return }
        let quality = quality ?? self.quality
        var request = PlaybackRequest(
            versionID: playing.versionID,
            audioTrack: playing.audioTrack,
            subtitles: playing.subtitleTrack.map(PlaybackRequest.Subtitles.track) ?? .off,
            // Auto streams no faster than Settings says.
            maxBitrate: quality == .auto ? playbackDefaults.autoMaxBitrate : quality.maxBitrate,
            playsOriginal: quality == .original,
            startPosition: playbackPosition
        )
        change(&request)
        changingStream?.cancel()
        changingStream = Task { [weak self, source, stopTranscoding] in
            guard let next = try? await source(request) else { return }
            // A stream it won't play, the server needn't go on making.
            guard let self, !Task.isCancelled else {
                await stopTranscoding?(next)
                return
            }
            if next.isSameFile(as: playing) {
                self.quality = quality
                return
            }
            // Playback stays where it was until the next stream is open, as it does through a seek: an
            // engine opening a stream can say it's at the start.
            let position = playbackPosition
            seekTarget = position
            defer { if seekTarget == position { finishSeeking() } }
            do {
                try await engine.load(next, startingAt: position)
                try Task.checkCancellation()
            } catch {
                // Closed, or a newer change took its place; anything else, the engine says itself.
                await stopTranscoding?(next)
                return
            }
            if !isPaused { engine.play() }
            self.playing = next
            self.quality = quality
            sendProgress()
            await stopTranscoding?(playing)
        }
    }

    /// Narrows the audio's range, or stops, and remembers it for the next player.
    public func setReducesLoudSounds(_ reduces: Bool) {
        guard reduces != reducesLoudSounds else { return }
        reducesLoudSounds = reduces
        preferences.set(reduces, forKey: Self.reducesLoudSoundsKey)
        engine?.setReducesLoudSounds(reduces)
    }

    /// Chooses the system caption style `id`, for every app, as the system player's Style menu does.
    /// Subtitles drawn as pictures can't take it, so they're turned off until Original is chosen again.
    public func chooseCaptionStyle(_ id: CaptionStyleOption.ID) {
        captionStyles.choose(id)
        chosenCaptionStyle = id
        setShowsOriginalSubtitles(false)
        if let showing = playing?.showingSubtitleTrack, !showing.isText {
            heldPictureTrack = showing.id
            applySubtitleTrack(nil)
        }
    }

    /// Shows subtitles as the file has them, its own colors and pictures as the disc drew them, and
    /// keeps it for the item. It never turns subtitles on: pictures chosen meanwhile show with On.
    public func chooseOriginalSubtitles() {
        setShowsOriginalSubtitles(true)
    }

    private func setShowsOriginalSubtitles(_ original: Bool) {
        guard original != showsOriginalSubtitles else { return }
        showsOriginalSubtitles = original
        rememberOriginalSubtitles?(original)
    }

    // MARK: Menus

    /// The menus, in the order they show: Subtitles while there are any, Audio, and More.
    public var menus: [PlayerMenu] {
        [subtitlesMenu, audioMenu, moreMenu].compactMap { $0 }
    }

    /// The menu open, or the submenu opened from it.
    public var openMenu: PlayerMenu? {
        guard let root = openMenuIDs.first, var menu = menus.first(where: { $0.id == root }) else { return nil }
        for id in openMenuIDs.dropFirst() {
            guard let submenu = menu.sections.flatMap(\.items).compactMap(\.submenu).first(where: { $0.id == id }) else { return nil }
            menu = submenu
        }
        return menu
    }

    /// How deep what's open is: 1 for a menu, 2 for a submenu opened from it, 0 for none.
    public var openMenuDepth: Int {
        openMenuIDs.count
    }

    /// Menu `id`, or a submenu of that name, as it is now, open or not: a menu closing shows what's
    /// chosen in it as it goes.
    public func menu(_ id: PlayerMenu.ID) -> PlayerMenu? {
        var menus = menus
        while let menu = menus.popLast() {
            if menu.id == id { return menu }
            menus += menu.sections.flatMap(\.items).compactMap(\.submenu)
        }
        return nil
    }

    /// Opens menu `id`, with focus on its first item.
    public func openMenu(_ id: PlayerMenu.ID) {
        guard let menu = menus.first(where: { $0.id == id }) else { return }
        openMenuIDs = [id]
        setOpenMenuRoot()
        menuFocus = menu.firstFocus(asSubmenu: false)
    }

    /// Select on an item: a choice is made and closes the menu, a toggle flips, and a submenu opens in
    /// the menu's place, with focus on what's chosen in it.
    public func choose(_ item: PlayerMenu.Item) {
        switch item.kind {
        case .submenu(let submenu):
            openMenuIDs.append(submenu.id)
            menuFocus = submenu.firstFocus(asSubmenu: true)
        case .toggle:
            item.action()
        case .choice:
            item.action()
            closeMenu()
        }
    }

    /// Menu: back to the menu a submenu opened from, with focus on where it opened from, or closed.
    public func goBackInMenu() {
        guard let closing = openMenuIDs.popLast() else { return }
        setOpenMenuRoot()
        menuFocus = openMenu?.sections.flatMap(\.items).first { $0.submenu?.id == closing }?.id
    }

    public func closeMenu() {
        openMenuIDs = []
        setOpenMenuRoot()
        menuFocus = nil
    }

    /// Changes `openMenuRoot` only when another menu, or none, is open, so what follows it alone isn't
    /// drawn again as submenus open and close.
    private func setOpenMenuRoot() {
        if openMenuRoot != openMenuIDs.first { openMenuRoot = openMenuIDs.first }
    }

    /// On or Off, and which under Language, and how they look under Style: Original, then the system's
    /// caption styles. Nil without any.
    private var subtitlesMenu: PlayerMenu? {
        guard !subtitleTracks.isEmpty else { return nil }
        let styles = captionStyleOptions
        let language = PlayerMenu(id: "subtitles.language", title: "Language", sections: [
            PlayerMenu.Section(id: "tracks", header: "Language", items: subtitleTracks.map { track in
                PlayerMenu.Item(id: "\(track.id)", title: track.title, kind: .choice(isChosen: track.id == subtitleTrack)) { [weak self] in
                    self?.selectSubtitleTrack(track.id)
                }
            }),
        ])
        let style = PlayerMenu(id: "subtitles.style", title: "Style", sections: [
            PlayerMenu.Section(id: "styles", header: "Style", items: [
                PlayerMenu.Item(id: Self.originalStyleID, title: "Original", kind: .choice(isChosen: showsOriginalSubtitles), captionStyle: .original) { [weak self] in
                    self?.chooseOriginalSubtitles()
                },
            ] + styles.map { option, appearance in
                let isChosen = !showsOriginalSubtitles && option.id == chosenCaptionStyle
                return PlayerMenu.Item(id: option.id, title: option.name, kind: .choice(isChosen: isChosen), captionStyle: appearance) { [weak self] in
                    self?.chooseCaptionStyle(option.id)
                }
            }),
        ])
        return PlayerMenu(id: "subtitles", title: "Subtitles", sections: [
            PlayerMenu.Section(id: "shows", header: "Subtitles", items: [
                PlayerMenu.Item(id: "on", title: "On", kind: .choice(isChosen: showsSubtitles)) { [weak self] in self?.showSubtitles(true) },
                PlayerMenu.Item(id: "off", title: "Off", kind: .choice(isChosen: !showsSubtitles)) { [weak self] in self?.showSubtitles(false) },
            ]),
            PlayerMenu.Section(id: "options", header: nil, items: [
                PlayerMenu.Item(id: "language", title: "Language", detail: subtitleTrackTitle, kind: .submenu(language)),
                PlayerMenu.Item(id: "style", title: "Style", detail: styleName, kind: .submenu(style)),
            ]),
        ])
    }

    /// The name of the style chosen.
    private var styleName: String? {
        showsOriginalSubtitles ? "Original" : captionStyleOptions.first { $0.0.id == chosenCaptionStyle }?.0.name
    }

    /// Reduce Loud Sounds, then which track.
    private var audioMenu: PlayerMenu {
        let adjustments = PlayerMenu.Section(id: "adjustments", header: "Audio Adjustments", items: [
            PlayerMenu.Item(id: "reduceLoudSounds", title: "Reduce Loud Sounds", kind: .toggle(isOn: reducesLoudSounds)) { [weak self] in
                guard let self else { return }
                setReducesLoudSounds(!reducesLoudSounds)
            },
        ])
        let tracks = PlayerMenu.Section(id: "tracks", header: "Audio Track", items: audioTracks.map { track in
            PlayerMenu.Item(id: "\(track.id)", title: track.title, kind: .choice(isChosen: track.id == audioTrack)) { [weak self] in
                self?.selectAudioTrack(track.id)
            }
        })
        return PlayerMenu(id: "audio", title: "Audio", sections: tracks.items.isEmpty ? [adjustments] : [adjustments, tracks])
    }

    /// Quality, which opens Auto and the bitrates.
    private var moreMenu: PlayerMenu {
        let qualities = PlayerMenu(id: "more.quality", title: "Quality", sections: [
            PlayerMenu.Section(id: "qualities", header: "Quality", items: qualities.map { quality in
                PlayerMenu.Item(id: quality.name, title: quality.name, kind: .choice(isChosen: quality == self.quality)) { [weak self] in
                    self?.selectQuality(quality)
                }
            }),
        ])
        return PlayerMenu(id: "more", title: "More", sections: [
            PlayerMenu.Section(id: "options", header: nil, items: [
                PlayerMenu.Item(id: "quality", title: "Quality", detail: quality.name, kind: .submenu(qualities)),
            ]),
        ])
    }

    // MARK: Reports

    /// How often it tells the server where playback is, as Jellyfin's web client does.
    public nonisolated static let progressInterval = Duration.seconds(10)

    /// Sends `report` once the reports before it have gone, so the server hears them in order: it saves
    /// the position from each, and a report arriving after the one saying it stopped would undo it.
    private func send(_ report: @escaping () async -> Void) {
        let previous = lastReport
        lastReport = Task {
            await previous?.value
            await report()
        }
    }

    /// Tells the server where playback is, and whether it's paused, once it has started.
    private func sendProgress() {
        guard let playing, let reportProgress else { return }
        let position = playbackPosition
        let isPaused = isPaused
        send { await reportProgress(playing, position, isPaused) }
    }

    private func startReportingProgress() {
        reportingProgress = Task { [weak self, progressInterval] in
            while true {
                do { try await Task.sleep(for: progressInterval) } catch { return }
                guard let self else { return }
                sendProgress()
            }
        }
    }

    /// Stops playing, and lets go of the media. If it had started, the server hears where it stopped:
    /// the end, if it played to the end. Closing again does nothing.
    public func close() {
        guard !isClosed else { return }
        isClosed = true
        hidingControls?.cancel()
        driving?.cancel()
        clearingSkipHint?.cancel()
        loadingPreview?.cancel()
        followingPlayback?.cancel()
        loading?.cancel()
        changingStream?.cancel()
        reportingProgress?.cancel()
        let position = hasEnded ? duration : playbackPosition
        engine?.stop()
        if let playing, let reportStopped {
            self.playing = nil
            send { await reportStopped(playing, position) }
        }
    }

    /// "Severance · S1E5" for an episode, else nil.
    static func subtitle(for item: MediaItem) -> String? {
        guard let episode = item.episode else { return nil }
        let parts = [episode.seriesName, episode.shortLabel].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func fail(with error: any Error) {
        failure = describe(error)
    }
}

private extension PlaybackSource {
    /// Whether it's the file `other` plays, as it is, with the same tracks, so there's nothing to open
    /// again.
    func isSameFile(as other: PlaybackSource) -> Bool {
        method == .directPlay && other.method == .directPlay && versionID == other.versionID
            && audioTrack == other.audioTrack && subtitleTrack == other.subtitleTrack
    }
}
