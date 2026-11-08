/// A Jellyfin user account.
public struct User: Hashable, Sendable, Identifiable, Codable {
    public let id: String
    public let name: String
    public let serverID: String?
    /// Reference to the user's avatar image, if they have one. Opaque, like `ImageTags`.
    public let primaryImageTag: String?

    public init(id: String, name: String, serverID: String?, primaryImageTag: String?) {
        self.id = id
        self.name = name
        self.serverID = serverID
        self.primaryImageTag = primaryImageTag
    }
}
