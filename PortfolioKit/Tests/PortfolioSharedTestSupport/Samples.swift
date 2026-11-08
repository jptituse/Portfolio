import Foundation
import PortfolioShared

extension UserSession {
    /// A signed-in session for tests that don't talk to a server.
    public static func sample(userName: String = "alex", token: String = "token-123") -> UserSession {
        UserSession(
            server: ServerInfo(
                id: "server-1",
                name: "Living Room",
                version: "10.11.2",
                url: URL(string: "http://tv.local:8096")!
            ),
            user: User(id: "user-1", name: userName, serverID: "server-1", primaryImageTag: nil),
            accessToken: token
        )
    }
}

/// An error to inject into fakes.
public struct TestError: Error, Hashable, Sendable {
    public let message: String

    public init(_ message: String = "test failure") {
        self.message = message
    }
}
