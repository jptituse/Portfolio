/// What a `PlaybackEngine` is doing.
public enum PlaybackStatus: Hashable, Sendable {
    /// Nothing is open.
    case idle
    /// Opening a source, until it first moves.
    case loading
    case playing
    case paused
    /// Waiting for media to go on: after a seek, or when it ran short.
    case buffering
    /// The source played to its end.
    case ended
    /// It couldn't open the source, or stopped partway. The engine's own description, for a log.
    case failed(String)
}
