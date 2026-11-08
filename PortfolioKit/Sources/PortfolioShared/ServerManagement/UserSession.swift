/// A signed-in user on a server, with the access token every authenticated request needs.
public struct UserSession: Hashable, Sendable {
    public let server: ServerInfo
    public let user: User
    public let accessToken: String

    public init(server: ServerInfo, user: User, accessToken: String) {
        self.server = server
        self.user = user
        self.accessToken = accessToken
    }
}

extension UserSession: CustomStringConvertible, CustomDebugStringConvertible {
    /// Never includes the access token, so sessions are safe to log.
    public var description: String { "UserSession(user: \(user.name), server: \(server.name))" }
    public var debugDescription: String { description }
}
