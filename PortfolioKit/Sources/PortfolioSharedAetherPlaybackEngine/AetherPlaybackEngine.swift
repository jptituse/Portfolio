import AetherEngine
import Observation
import PortfolioShared
import PortfolioSharedPlaybackEngine
import SwiftUI

/// A `PlaybackEngine` that plays through AetherEngine, the one type outside this module that knows it.
/// It mirrors the engine's Combine state as observable properties.
///
/// One engine per player: AetherEngine binds to one surface, and `stop()` tears its session down.
@MainActor
@Observable
public final class AetherPlaybackEngine: PlaybackEngine {
    public private(set) var status: PlaybackStatus = .idle
    public private(set) var currentTime: Duration = .zero
    public private(set) var duration: Duration = .zero

    @ObservationIgnored private let engine: AetherEngine
    @ObservationIgnored private var mirroring: [Task<Void, Never>] = []
    @ObservationIgnored private let preferences: PlaybackPreferences

    /// - Parameter preferences: how this device plays, as Settings has it when the player opens.
    /// - Throws: if AetherEngine can't start, such as when its audio session is unavailable.
    public init(preferences: PlaybackPreferences = PlaybackPreferences()) throws {
        self.preferences = preferences
        engine = try AetherEngine()
        mirroring = [
            Task { [weak self, engine] in
                for await phase in engine.$playbackPhase.values { self?.status = Self.status(for: phase) }
            },
            Task { [weak self, engine] in
                for await seconds in engine.clock.$currentTime.values { self?.currentTime = .seconds(seconds) }
            },
            Task { [weak self, engine] in
                for await seconds in engine.$duration.values { self?.duration = .seconds(seconds) }
            },
        ]
    }

    /// The engine's name and version, for About.
    public nonisolated static let about = (name: "AetherEngine", version: AetherEngine.version)

    isolated deinit {
        mirroring.forEach { $0.cancel() }
    }

    public var surface: AnyView {
        AnyView(AetherPlayerSurface(engine: engine))
    }

    public func load(_ source: PlaybackSource, startingAt position: Duration) async throws {
        try await engine.load(
            url: source.url,
            startPosition: position > .zero ? position.inSeconds : nil,
            options: Self.options(for: source, preferences)
        )
    }

    /// How AetherEngine opens `source` as `preferences` say.
    ///
    /// - Dolby Vision FEL composes Profile 7 from both its layers (`preferDualLayerDolbyVision`) on the
    ///   engine's own decoder, or with AVPlayer decoding the base layer. Without it, Profile 7 plays as
    ///   single-layer 8.1 without its enhancement layer.
    /// - Object audio renders TrueHD Atmos and DTS:X for the speakers, which tvOS sends to the receiver
    ///   as Dolby MAT. Without it, it becomes lossy E-AC-3 5.1 without heights.
    /// - Enhancing dialogue and mixing down to stereo shape decoded audio, so audio that would pass
    ///   through as it is (Atmos, lossless) is decoded, and object audio isn't rendered meanwhile.
    nonisolated static func options(for source: PlaybackSource, _ preferences: PlaybackPreferences) -> LoadOptions {
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
        options.audioShaping = AudioShaping(
            maxChannels: preferences.downmixesToStereo ? 2 : nil,
            dialogueGainDB: preferences.enhancesDialogue ? dialogueGain : 0
        )
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
        engine.play()
    }

    public func pause() {
        engine.pause()
    }

    public func seek(to position: Duration) async {
        await engine.seek(to: position.inSeconds)
    }

    public func stop() {
        engine.stop()
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
