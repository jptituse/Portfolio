import Observation
import PortfolioShared
import SwiftUI

/// Plays one source at a time and shows its picture, whichever engine does it. Feature code drives
/// playback through this, so only the engine's own module knows which engine that is.
@MainActor
public protocol PlaybackEngine: AnyObject, Observable {
    /// What it's doing.
    var status: PlaybackStatus { get }
    /// Where playback is in the source.
    var currentTime: Duration { get }
    /// How long the source is: zero until it's known.
    var duration: Duration { get }
    /// The picture, filling the space it's given.
    var surface: AnyView { get }
    /// The subtitles showing, drawn where they go over the picture, filling the same space.
    var subtitles: AnyView { get }

    /// Opens `source`, in place of anything open before, ready to play from `position`, on the source's
    /// `audioTrack` with its `subtitleTrack` showing.
    ///
    /// - Throws: why it couldn't be opened; `CancellationError` if another load or `stop()` took its
    ///   place, or the task was cancelled.
    func load(_ source: PlaybackSource, startingAt position: Duration) async throws
    func play()
    func pause()
    func seek(to position: Duration) async
    /// Switches to `track`, one of the open source's audio tracks in the stream, playing on from where
    /// playback is.
    func selectAudioTrack(_ track: MediaTrack)
    /// Shows `track`, one of the open source's subtitle tracks in the stream or in a file of its own, or
    /// no subtitles.
    func selectSubtitleTrack(_ track: MediaTrack?)
    /// Narrows the audio's range, so loud scenes are quieter and quiet ones louder, from now on and in
    /// whatever opens next, or stops.
    func setReducesLoudSounds(_ reduces: Bool)
    /// Ends the session and lets go of the source, its connections and the display mode it set.
    func stop()
}
