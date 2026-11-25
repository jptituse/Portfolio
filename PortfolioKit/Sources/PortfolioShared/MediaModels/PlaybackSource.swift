import Foundation

/// Where an item's media plays from: a URL, and the HTTP headers its server needs to send it, with the
/// version's audio and subtitle tracks and which of them are playing.
public struct PlaybackSource: Hashable, Sendable {
    /// How the server sends the media.
    public enum Method: Hashable, Sendable {
        /// The file as it is.
        case directPlay
        /// A stream the server makes from the file: at a lower bitrate, with other tracks, or in a form
        /// the player plays.
        case transcode
    }

    public let url: URL
    /// Sent with every request for the media, such as the server's sign-in header.
    public let httpHeaders: [String: String]
    /// Which of the item's versions it is, as its server names it, for reporting playback.
    public let versionID: String?
    /// The server's name for this playback, for reporting it.
    public let playSessionID: String?
    public let method: Method
    /// The version's audio tracks, in its order.
    public let audioTracks: [MediaTrack]
    /// The version's subtitle tracks, in its order.
    public let subtitleTracks: [MediaTrack]
    /// The audio track playing, or nil if there's none.
    public var audioTrack: MediaTrack.ID?
    /// The subtitles showing, or nil while they're off.
    public var subtitleTrack: MediaTrack.ID?
    /// The version's bitrate as it is, in bits per second, if known.
    public let bitrate: Int?

    public init(
        url: URL,
        httpHeaders: [String: String] = [:],
        versionID: String? = nil,
        playSessionID: String? = nil,
        method: Method = .directPlay,
        audioTracks: [MediaTrack] = [],
        subtitleTracks: [MediaTrack] = [],
        audioTrack: MediaTrack.ID? = nil,
        subtitleTrack: MediaTrack.ID? = nil,
        bitrate: Int? = nil
    ) {
        self.url = url
        self.httpHeaders = httpHeaders
        self.versionID = versionID
        self.playSessionID = playSessionID
        self.method = method
        self.audioTracks = audioTracks
        self.subtitleTracks = subtitleTracks
        self.audioTrack = audioTrack
        self.subtitleTrack = subtitleTrack
        self.bitrate = bitrate
    }

    /// The audio track playing.
    public var playingAudioTrack: MediaTrack? {
        audioTracks.first { $0.id == audioTrack }
    }

    /// The subtitles showing.
    public var showingSubtitleTrack: MediaTrack? {
        subtitleTracks.first { $0.id == subtitleTrack }
    }
}
