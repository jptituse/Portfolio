import AetherEngine
import Observation
import PortfolioShared
import PortfolioSharedPlaybackEngine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A `PlaybackEngine` that plays through AetherEngine, the one type outside this module that knows it.
/// It mirrors the engine's Combine state as observable properties, and draws the subtitles AetherEngine
/// leaves to its host (`SubtitlesView`).
///
/// One engine per player: AetherEngine binds to one surface, and `stop()` tears its session down.
///
/// On tvOS, AetherEngine lets go of the video as the app goes to the background, so nothing it holds is
/// wedged through a suspension, and leaves opening it again to its host: this opens it again at the
/// playhead once the app is back (`reloadAtCurrentPosition()`), playing or paused as it was last asked.
/// Without it, coming back to a movie left it never loading.
@MainActor
@Observable
public final class AetherPlaybackEngine: PlaybackEngine {
    public private(set) var status: PlaybackStatus = .idle
    public private(set) var currentTime: Duration = .zero
    public private(set) var duration: Duration = .zero

    @ObservationIgnored private let engine: AetherEngine
    @ObservationIgnored private let subtitlesViewModel: SubtitlesViewModel
    @ObservationIgnored private var mirroring: [Task<Void, Never>] = []
    @ObservationIgnored private let preferences: PlaybackPreferences
    /// What's open, for which of the engine's tracks its tracks are.
    @ObservationIgnored private var source: PlaybackSource?
    @ObservationIgnored private var reducesLoudSounds = false
    /// Where playback was while the engine rebuilds itself at the playhead, and when the hold gives up.
    @ObservationIgnored private var rebuildHold: RebuildHold?
    @ObservationIgnored private var rebuildTimeout: Task<Void, Never>?
    /// Whether it was last asked to play rather than pause, which opening again keeps: AetherEngine,
    /// left to itself, plays.
    @ObservationIgnored private var playsWhenOpen = false
    /// Whether the app went to the background with something open, so the engine has let go of it.
    @ObservationIgnored private var isBackgrounded = false
    @ObservationIgnored private var lifecycleObservers: [any NSObjectProtocol] = []

    /// - Parameter preferences: how this device plays, as Settings has it when the player opens.
    /// - Throws: if AetherEngine can't start, such as when its audio session is unavailable.
    public init(preferences: PlaybackPreferences = PlaybackPreferences()) throws {
        self.preferences = preferences
        engine = try AetherEngine()
        // Nothing here moves subtitles in time, so the engine needn't keep pictures it has drawn.
        engine.maximumSubtitleOffsetSeconds = 0
        subtitlesViewModel = SubtitlesViewModel(engine: engine)
        mirroring = [
            Task { [weak self, engine] in
                for await phase in engine.$playbackPhase.values { self?.status = Self.status(for: phase) }
            },
            Task { [weak self, engine] in
                for await seconds in engine.clock.$currentTime.values { self?.clockMoved(to: .seconds(seconds)) }
            },
            Task { [weak self, engine] in
                for await seconds in engine.$duration.values {
                    // Rebuilding, it doesn't know for a moment.
                    if seconds > 0 || self?.rebuildHold == nil { self?.duration = .seconds(seconds) }
                }
            },
        ]
        #if canImport(UIKit)
        let center = NotificationCenter.default
        let background = UIApplication.didEnterBackgroundNotification
        let active = UIApplication.didBecomeActiveNotification
        lifecycleObservers = [
            center.addObserver(forName: background, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.enteredBackground() }
            },
            center.addObserver(forName: active, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.becameActive() }
            },
        ]
        #endif
    }

    /// The engine's name and version, for About.
    public nonisolated static let about = (name: "AetherEngine", version: AetherEngine.version)

    isolated deinit {
        mirroring.forEach { $0.cancel() }
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
    }

    public var surface: AnyView {
        AnyView(AetherPlayerSurface(engine: engine))
    }

    public var subtitles: AnyView {
        AnyView(SubtitlesView(viewModel: subtitlesViewModel))
    }

    /// Opens `source` with its subtitle files, on its audio track: the file's tracks are only known once
    /// it's open, so it opens on that track's language, then switches if that picked another.
    public func load(_ source: PlaybackSource, startingAt position: Duration) async throws {
        endRebuildHold()
        self.source = source
        playsWhenOpen = false
        var options = Self.options(for: source, preferences, reducesLoudSounds: reducesLoudSounds)
        options.externalSubtitles = TrackNumbering.subtitleFiles(in: source).map { file in
            ExternalSubtitleTrack(
                url: file.url,
                name: file.track.title,
                language: file.track.language,
                isForced: file.track.isForced,
                isDefault: file.track.isDefault
            )
        }
        // A stream the server makes carries only the audio it was asked for.
        let audio = source.method == .directPlay ? source.playingAudioTrack : nil
        if let language = audio?.language {
            options.preferredAudioLanguages = [language]
        }
        let probe = try await engine.load(url: source.url, startPosition: position > .zero ? position.inSeconds : nil, options: options)
        subtitlesViewModel.videoSize = probe.flatMap { probe in
            probe.videoWidth > 0 && probe.videoHeight > 0 ? CGSize(width: Int(probe.videoWidth), height: Int(probe.videoHeight)) : nil
        }
        if let audio, let id = engineTrackID(for: audio), id != engine.activeAudioTrackIndex {
            holdTime(at: position)
            engine.selectAudioTrack(index: id)
        }
        selectSubtitleTrack(source.showingSubtitleTrack)
    }

    /// How AetherEngine opens `source` as `preferences` say, and Reduce Loud Sounds if it's on.
    ///
    /// - Dolby Vision FEL composes Profile 7 from both its layers (`preferDualLayerDolbyVision`) on the
    ///   engine's own decoder, or with AVPlayer decoding the base layer. Without it, Profile 7 plays as
    ///   single-layer 8.1 without its enhancement layer.
    /// - Object audio renders TrueHD Atmos and DTS:X for the speakers, which tvOS sends to the receiver
    ///   as Dolby MAT. Without it, it becomes lossy E-AC-3 5.1 without heights.
    /// - Enhancing dialogue, mixing down to stereo and reducing loud sounds shape decoded audio, so audio
    ///   that would pass through as it is (Atmos, lossless) is decoded, and object audio isn't rendered
    ///   meanwhile.
    nonisolated static func options(for source: PlaybackSource, _ preferences: PlaybackPreferences, reducesLoudSounds: Bool = false) -> LoadOptions {
        var options = LoadOptions(httpHeaders: source.httpHeaders)
        switch preferences.dolbyVisionFEL {
        case .off:
            options.preferDualLayerDolbyVision = false
        case .full:
            options.preferDualLayerDolbyVision = true
            options.dualLayerRoute = .softwareHost
        case .fullThroughAVPlayer:
            options.preferDualLayerDolbyVision = true
            options.dualLayerRoute = .avPlayerOutput
        }
        options.objectAudioRendering = preferences.objectAudioLayout.map { .render(speakerLayout(for: $0)) } ?? .off
        options.upscalesLowResolutionVideo = preferences.upscalesLowResolution
        options.audioShaping = audioShaping(preferences, reducesLoudSounds: reducesLoudSounds)
        options.audioDelaySeconds = preferences.audioDelay.inSeconds
        return options
    }

    nonisolated static func speakerLayout(for layout: SpeakerLayout) -> SpatialSpeakerLayout {
        switch layout {
        case .l512: .l512
        case .l514: .l514
        case .l712: .l712
        case .l714: .l714
        case .l916: .l916
        }
    }

    /// How much Enhance Dialogue raises the dialogue, in dB: half the most the engine allows, past which
    /// a centre channel starts to sound like a separate speaker.
    nonisolated static let dialogueGain = AudioShaping.maxDialogueGainDB / 2

    public func play() {
        playsWhenOpen = true
        engine.play()
    }

    public func pause() {
        playsWhenOpen = false
        engine.pause()
    }

    public func seek(to position: Duration) async {
        endRebuildHold()
        await engine.seek(to: position.inSeconds)
    }

    /// Switches to `track`, which AetherEngine does by opening the file again at the playhead.
    public func selectAudioTrack(_ track: MediaTrack) {
        guard let id = engineTrackID(for: track), id != engine.activeAudioTrackIndex else { return }
        holdTime(at: currentTime)
        engine.selectAudioTrack(index: id)
    }

    public func selectSubtitleTrack(_ track: MediaTrack?) {
        guard let track, let id = engineTrackID(for: track) else {
            if engine.activeSubtitleTrackIndex != nil { engine.clearSubtitle() }
            return
        }
        guard id != engine.activeSubtitleTrackIndex else { return }
        engine.selectSubtitleTrack(index: id)
    }

    /// Compresses the audio with AetherEngine's night-mode preset, which decodes audio it would otherwise
    /// pass through as it is (Dolby Atmos and lossless audio among it) while it's on. Changing it reopens
    /// the audio, for about a second. AVPlayer owns the audio of a stream the server makes, so it waits for
    /// a file played as it is.
    public func setReducesLoudSounds(_ reduces: Bool) {
        // The engine opens a file it plays as it is again at the playhead to change it.
        if reduces != reducesLoudSounds, source?.method == .directPlay { holdTime(at: currentTime) }
        reducesLoudSounds = reduces
        engine.setAudioShaping(Self.audioShaping(preferences, reducesLoudSounds: reduces))
    }

    public func stop() {
        endRebuildHold()
        source = nil
        engine.stop()
    }

    private func enteredBackground() {
        if source != nil { isBackgrounded = true }
    }

    /// Back from the background: opens what it let go of again at the playhead, holding the time there
    /// meanwhile, then plays or pauses as it was last asked. A becoming active that follows no trip to
    /// the background, such as after a system alert, has nothing to open.
    private func becameActive() {
        guard isBackgrounded else { return }
        isBackgrounded = false
        guard let opened = source else { return }
        holdTime(at: currentTime)
        Task { [weak self, engine] in
            try? await engine.reloadAtCurrentPosition()
            guard let self, source == opened else { return }
            if playsWhenOpen { engine.play() } else { engine.pause() }
        }
    }

    /// Keeps the time where playback is, `position`, while the engine rebuilds itself there.
    private func holdTime(at position: Duration) {
        rebuildHold = RebuildHold(at: position)
        currentTime = position
        rebuildTimeout?.cancel()
        rebuildTimeout = Task { [weak self] in
            try? await Task.sleep(for: RebuildHold.timeout)
            guard !Task.isCancelled, let self else { return }
            endRebuildHold()
            currentTime = .seconds(engine.clock.currentTime)
        }
    }

    private func endRebuildHold() {
        rebuildHold = nil
        rebuildTimeout?.cancel()
        rebuildTimeout = nil
    }

    private func clockMoved(to time: Duration) {
        if var hold = rebuildHold {
            guard hold.isOver(at: time) else {
                rebuildHold = hold
                return
            }
            endRebuildHold()
        }
        currentTime = time
    }

    /// The audio's shaping: Settings' dialogue and stereo, with the night-mode compressor while Reduce
    /// Loud Sounds is on.
    nonisolated static func audioShaping(_ preferences: PlaybackPreferences, reducesLoudSounds: Bool) -> AudioShaping {
        AudioShaping(
            maxChannels: preferences.downmixesToStereo ? 2 : nil,
            dialogueGainDB: preferences.enhancesDialogue ? dialogueGain : 0,
            compressor: reducesLoudSounds ? .night : nil
        )
    }

    private func engineTrackID(for track: MediaTrack) -> Int? {
        guard let source else { return nil }
        return TrackNumbering.engineTrackID(for: track, in: source, audio: engine.audioTracks, subtitles: engine.subtitleTracks)
    }

    /// What AetherEngine's phase, which tracks motion rather than intent, means here. Seeking, running
    /// short and reconnecting are all waiting for media.
    nonisolated static func status(for phase: PlaybackPhase) -> PlaybackStatus {
        switch phase {
        case .idle: .idle
        case .loading: .loading
        case .playing: .playing
        case .paused: .paused
        case .seeking, .rebuffering, .stalled: .buffering
        case .ended: .ended
        case .error(let message): .failed(message)
        }
    }
}
