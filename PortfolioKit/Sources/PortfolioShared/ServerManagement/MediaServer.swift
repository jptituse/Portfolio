/// A server added on this device: the people on it that the device knows, and which of them are
/// signed in here.
public struct MediaServer: Hashable, Sendable, Codable, Identifiable {
    public var server: ServerInfo
    /// The server's listed users in its order, then anyone else who signed in on this device.
    public var users: [User]
    /// Access tokens of the users signed in on this device, by user ID.
    var accessTokens: [User.ID: String]

    public var id: String { server.id }

    public init(server: ServerInfo, users: [User] = [], accessTokens: [User.ID: String] = [:]) {
        self.server = server
        self.users = users
        self.accessTokens = accessTokens
    }

    /// The user's session, if they're signed in on this device.
    public func session(for userID: User.ID) -> UserSession? {
        guard let user = users.first(where: { $0.id == userID }),
            let token = accessTokens[userID] else {
            return nil
        }
        return UserSession(server: server, user: user, accessToken: token)
    }

    public func isSignedIn(_ userID: User.ID) -> Bool {
        accessTokens[userID] != nil
    }

    /// Adds the user, or replaces what was known about them.
    mutating func remember(_ user: User) {
        if let index = users.firstIndex(where: { $0.id == user.id }) {
            users[index] = user
        } else {
            users.append(user)
        }
    }

    /// Takes the server's listed users, in its order, keeping anyone else this device already knew.
    mutating func update(listedUsers: [User]) {
        let listed = Set(listedUsers.map(\.id))
        users = listedUsers + users.filter { !listed.contains($0.id) }
    }
}
