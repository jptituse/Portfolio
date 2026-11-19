/// Where playing an item starts.
public enum PlaybackStart: Hashable, Sendable {
    /// From the beginning.
    case beginning
    /// From where the user left off, wherever they played it last: the server's position when Play is
    /// pressed.
    case resuming
}
