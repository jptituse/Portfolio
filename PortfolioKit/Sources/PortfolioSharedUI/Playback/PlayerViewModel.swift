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
/// `controlsTimeout` while it plays, staying while it's paused. Playing and pausing, and scrubbing
/// while paused (picking a spot, then playing from it), go through here.
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
    @ObservationIgnored private let source: () async throws -> PlaybackSource
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
    /// What's playing, once it has started, until it stops.
    @ObservationIgnored private var playing: PlaybackSource?
    @ObservationIgnored private var isClosed = false
    @ObservationIgnored private let controlsTimeout: Duration
    @ObservationIgnored private var hidingControls: Task<Void, Never>?

    /// Whether the transport bar shows.
    public private(set) var showsControls = false
    /// Where scrubbing would take playback, while scrubbing.
    public private(set) var scrubPosition: Duration?
    /// Whether it's been paused: what was asked for, which the engine says a moment later, and not while
    /// it seeks.
    public private(set) var isPaused = false
    /// Where a seek is taking playback, until it's there.
    private var seekTarget: Duration?
    /// Why it can't play, found before the engine had anything to play.
    private var failure: String?
    /// Whether it's still starting: from `start()` until it's asked to play.
    private var isStarting = false

    /// - Parameters:
    ///   - makeEngine: the engine to play it in.
    ///   - position: finds where to start in it, once `source` has found where it plays from.
    ///   - source: finds where it plays from, such as by asking its server.
    ///   - describe: why `source` failed, in words.
    ///   - reportStarted: tells the server playback started from a source, at a position.
    ///   - reportProgress: tells it where playback is, and whether it's paused.
    ///   - reportStopped: tells it where playback stopped.
    ///   - controlsTimeout: how long the controls stay while it plays and nothing is pressed.
    ///   - progressInterval: how often it reports where playback is.
    init(
        title: String,
        subtitle: String? = nil,
        makeEngine: () throws -> any PlaybackEngine,
        startingAt position: @escaping () async -> Duration = { .zero },
        source: @escaping () async throws -> PlaybackSource,
        describe: @escaping (any Error) -> String,
        reportStarted: ((PlaybackSource, Duration) async -> Void)? = nil,
        reportProgress: ((PlaybackSource, Duration, Bool) async -> Void)? = nil,
        reportStopped: ((PlaybackSource, Duration) async -> Void)? = nil,
        controlsTimeout: Duration = PlayerViewModel.controlsTimeout,
        progressInterval: Duration = PlayerViewModel.progressInterval
    ) {
        self.title = title
        self.subtitle = subtitle
        self.controlsTimeout = controlsTimeout
        self.progressInterval = progressInterval
        self.source = source
        self.describe = describe
        self.reportStarted = reportStarted
        self.reportProgress = reportProgress
        self.reportStopped = reportStopped
        startPosition = position
        do {
            engine = try makeEngine()
        } catch {
            engine = nil
            failure = "Playback isn't available right now."
        }
    }

    /// Plays `source` as it is from the beginning, such as a test video, with nothing to ask a server
    /// first.
    public convenience init(title: String, source: PlaybackSource, makeEngine: () throws -> any PlaybackEngine) {
        self.init(title: title, makeEngine: makeEngine, source: { source }, describe: { _ in "Couldn't open \(title)." })
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

    /// Finds where it plays from, opens it there and plays it. It starts once; asking again does
    /// nothing.
    public func start() {
        guard loading == nil, let engine else { return }
        isStarting = true
        loading = Task { [weak self, source, startPosition, reportStarted] in
            // Failing, too, it's no longer starting.
            defer { self?.isStarting = false }
            do {
                let found = try await source()
                let position = await startPosition()
                try Task.checkCancellation()
                try await engine.load(found, startingAt: position)
                engine.play()
                guard let self else { return }
                isStarting = false
                playing = found
                if let reportStarted { send { await reportStarted(found, position) } }
                startReportingProgress()
            } catch is CancellationError {
                // Closed meanwhile.
            } catch {
                // The engine says why it failed itself; anything before it didn't get that far.
                if case .failed = engine.status { return }
                self?.fail(with: error)
            }
        }
    }

    // MARK: Controls

    /// Where playback is: where scrubbing would take it, while scrubbing, and where a seek is taking it.
    public var position: Duration {
        scrubPosition ?? playbackPosition
    }

    /// Where playback is, or where a seek is taking it, whatever spot scrubbing has picked.
    private var playbackPosition: Duration {
        seekTarget ?? engine?.currentTime ?? .zero
    }

    /// How long the media is: zero until it's known.
    public var duration: Duration {
        engine?.duration ?? .zero
    }

    /// How far through the media `position` is, from 0 to 1.
    public var progress: Double {
        guard duration > .zero else { return 0 }
        return min(1, max(0, position / duration))
    }

    /// How far through the media playback is, from 0 to 1, whatever spot scrubbing has picked.
    public var playbackProgress: Double {
        guard duration > .zero else { return 0 }
        return min(1, max(0, playbackPosition / duration))
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

    /// Select or Play/Pause: plays from the spot picked while scrubbing, or else pauses or plays.
    public func togglePlayPause() {
        guard let engine else { return }
        if let target = scrubPosition {
            scrubPosition = nil
            isPaused = false
            seek(to: target)
        } else if isPaused {
            isPaused = false
            engine.play()
        } else {
            isPaused = true
            engine.pause()
        }
        showControls()
        sendProgress()
    }

    /// Moves playback to `target`, then plays or stays paused as it was asked: an engine can come out of
    /// a seek playing.
    private func seek(to target: Duration) {
        guard let engine else { return }
        seekTarget = target
        Task { [weak self] in
            await engine.seek(to: target)
            guard let self, self.seekTarget == target else { return }
            self.seekTarget = nil
            if self.isPaused { engine.pause() } else { engine.play() }
        }
    }

    /// Starts picking a spot to play from, while paused.
    public func beginScrubbing() {
        guard isPaused else { return }
        if scrubPosition == nil { scrubPosition = position }
        showControls()
    }

    /// Moves the spot to `fraction` of the way through the media, as the bar's needle moves there. At
    /// `playbackProgress` it's exactly where playback is.
    public func scrub(to fraction: Double) {
        guard isScrubbing, duration > .zero else { return }
        scrubPosition = fraction == playbackProgress ? playbackPosition : duration * min(1, max(0, fraction))
        showControls()
    }

    /// Menu while scrubbing: puts the spot back where playback is.
    public func cancelScrubbing() {
        scrubPosition = nil
        showControls()
    }

    /// Hides the controls after `controlsTimeout`, unless it's paused or scrubbing.
    private func scheduleHidingControls() {
        hidingControls?.cancel()
        guard !isPaused, !isScrubbing else { return }
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
        loading?.cancel()
        reportingProgress?.cancel()
        let position = hasEnded ? duration : engine?.currentTime ?? .zero
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
