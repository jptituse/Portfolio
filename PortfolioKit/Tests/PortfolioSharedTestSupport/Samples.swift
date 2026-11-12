import Foundation
import PortfolioShared

extension UserSession {
    /// A signed-in session for tests that don't talk to a server.
    public static func sample(
        userID: String = "user-1",
        userName: String = "alex",
        token: String = "token-123",
        server: ServerInfo = .sample()
    ) -> UserSession {
        UserSession(
            server: server,
            user: User(id: userID, name: userName, serverID: server.id, primaryImageTag: nil),
            accessToken: token
        )
    }
}

extension ServerInfo {
    /// A server for tests that don't talk to one.
    public static func sample(id: String = "server-1", name: String = "Living Room", url: String = "http://tv.local:8096") -> ServerInfo {
        ServerInfo(id: id, name: name, version: "10.11.2", url: URL(string: url)!)
    }
}

/// An error to inject into fakes.
public struct TestError: Error, Hashable, Sendable {
    public let message: String

    public init(_ message: String = "test failure") {
        self.message = message
    }
}
