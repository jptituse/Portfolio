import Foundation

/// Where an item's media plays from: a URL, and the HTTP headers its server needs to send it.
public struct PlaybackSource: Hashable, Sendable {
    public let url: URL
    /// Sent with every request for the media, such as the server's sign-in header.
    public let httpHeaders: [String: String]
    /// Which of the item's versions it is, as its server names it, for reporting playback.
    public let versionID: String?
    /// The server's name for this playback, for reporting it.
    public let playSessionID: String?

    public init(url: URL, httpHeaders: [String: String] = [:], versionID: String? = nil, playSessionID: String? = nil) {
        self.url = url
        self.httpHeaders = httpHeaders
        self.versionID = versionID
        self.playSessionID = playSessionID
    }
}
