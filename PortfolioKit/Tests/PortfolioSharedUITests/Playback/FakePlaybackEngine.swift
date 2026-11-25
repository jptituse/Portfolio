import Foundation
import Observation
import PortfolioShared
import PortfolioSharedPlaybackEngine
import SwiftUI

/// A `PlaybackEngine` that records what it's asked to do, and plays nothing.
@MainActor
@Observable
final class FakePlaybackEngine: PlaybackEngine {
    var status: PlaybackStatus = .idle
    var currentTime: Duration = .zero
    var duration: Duration = .zero
    var surface: AnyView { AnyView(EmptyView()) }
    var subtitles: AnyView { AnyView(EmptyView()) }

    /// What it was asked to open, and from where.
    private(set) var loads: [(source: PlaybackSource, position: Duration)] = []
    private(set) var isPlaying = false
    /// The tracks it was asked to switch to, in order; nil for subtitles off.
    private(set) var audioTrackChoices: [MediaTrack.ID] = []
    private(set) var subtitleTrackChoices: [MediaTrack.ID?] = []
    private(set) var reducesLoudSounds = false
    private(set) var isStopped = false
    /// Thrown from `load`, as an engine that can't open the source would, also saying it failed.
    var loadFailure: String?
    /// Whether it comes out of a seek playing, as AetherEngine can.
    var playsAfterSeeking = false
    /// Holds `load` until `finishLoading()`, saying it's paused meanwhile, as AetherEngine does while the
    /// TV switches modes.
    var holdsLoad = false
    private var heldLoad: CheckedContinuation<Void, Never>?

    func finishLoading() {
        heldLoad?.resume()
        heldLoad = nil
    }

    func load(_ source: PlaybackSource, startingAt position: Duration) async throws {
        loads.append((source, position))
        status = .loading
        if let loadFailure {
            status = .failed(loadFailure)
            throw URLError(.cannotDecodeContentData)
        }
        if holdsLoad {
            status = .paused
            await withCheckedContinuation { heldLoad = $0 }
        }
        // Open, it waits to be told to play.
        isPlaying = false
        status = .paused
    }

    func play() {
        isPlaying = true
        status = .playing
    }

    func pause() {
        isPlaying = false
        status = .paused
    }

    func selectAudioTrack(_ track: MediaTrack) {
        audioTrackChoices.append(track.id)
    }

    func selectSubtitleTrack(_ track: MediaTrack?) {
        subtitleTrackChoices.append(track?.id)
    }

    func setReducesLoudSounds(_ reduces: Bool) {
        reducesLoudSounds = reduces
    }

    func seek(to position: Duration) async {
        currentTime = position
        if playsAfterSeeking { status = .playing }
    }

    func stop() {
        isStopped = true
        status = .idle
    }
}
