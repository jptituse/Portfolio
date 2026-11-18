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

    /// - Throws: if AetherEngine can't start, such as when its audio session is unavailable.
    public init() throws {
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
            options: LoadOptions(httpHeaders: source.httpHeaders)
        )
    }

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
