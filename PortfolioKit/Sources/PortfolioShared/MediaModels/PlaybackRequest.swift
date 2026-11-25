/// How a player asks for an item to be sent: which version and tracks, how fast a stream at most or the
/// file as it is whatever the server would rather, and from where. What it leaves out, the server picks
/// for the user.
public struct PlaybackRequest: Hashable, Sendable {
    /// Which subtitles to show.
    public enum Subtitles: Hashable, Sendable {
        case off
        case track(MediaTrack.ID)
    }

    /// Which of the item's versions to play, or nil for its default.
    public var versionID: String?
    /// The audio track to play, or nil for the one the server picks for the user.
    public var audioTrack: MediaTrack.ID?
    /// The subtitles to show, or nil for what the server picks for the user.
    public var subtitles: Subtitles?
    /// The highest bitrate to stream at, in bits per second, or nil to play the file as it is wherever it
    /// can.
    public var maxBitrate: Int?
    /// Whether to play the file as it is even where the server would rather make a stream, such as above
    /// its limit for connections from outside its network. What only a stream the server makes could
    /// carry, such as subtitles it draws into the picture, is left out.
    public var playsOriginal: Bool
    /// Where playback will start, so a stream the server makes starts there.
    public var startPosition: Duration

    public init(
        versionID: String? = nil,
        audioTrack: MediaTrack.ID? = nil,
        subtitles: Subtitles? = nil,
        maxBitrate: Int? = nil,
        playsOriginal: Bool = false,
        startPosition: Duration = .zero
    ) {
        self.versionID = versionID
        self.audioTrack = audioTrack
        self.subtitles = subtitles
        self.maxBitrate = maxBitrate
        self.playsOriginal = playsOriginal
        self.startPosition = startPosition
    }
}
