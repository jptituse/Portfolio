/// A user account on a media server.
public struct User: Hashable, Sendable, Identifiable, Codable {
    public let id: String
    public let name: String
    public let serverID: String?
    /// Reference to the user's avatar image, if they have one. Opaque, like `ImageTags`.
    public let primaryImageTag: String?
    /// Whether signing in needs a password. Some accounts, often children's, have none.
    public let hasPassword: Bool

    public init(id: String, name: String, serverID: String?, primaryImageTag: String?, hasPassword: Bool = true) {
        self.id = id
        self.name = name
        self.serverID = serverID
        self.primaryImageTag = primaryImageTag
        self.hasPassword = hasPassword
    }
}
