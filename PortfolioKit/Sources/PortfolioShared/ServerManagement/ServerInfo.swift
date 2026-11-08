import Foundation

/// A media server the app has checked and can talk to.
public struct ServerInfo: Hashable, Sendable {
    /// The server's stable ID, which survives URL changes.
    public let id: String
    public let name: String
    /// The version the server reports, for display. Compatibility checks belong to the server
    /// integration that validated it.
    public let version: String
    /// The address the app reached the server at.
    public let url: URL

    public init(id: String, name: String, version: String, url: URL) {
        self.id = id
        self.name = name
        self.version = version
        self.url = url
    }
}
