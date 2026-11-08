import Foundation
import JellyfinAPI
import PortfolioShared

extension JellyfinServerClient: SessionAuthority {
    /// Checks the session with `/Users/Me`, which answers only for a token the server still accepts.
    public func check(_ session: UserSession) async -> SessionCheck {
        do {
            let dto = try await perform(.request) {
                try await makeClient(url: session.server.url, accessToken: session.accessToken)
                    .send(Paths.getCurrentUser).value
            }
            return User(dto).map(SessionCheck.valid) ?? .unavailable
        } catch JellyfinError.unauthorized {
            return .revoked
        } catch {
            // Offline, failing or cancelled: none of these say anything about the token.
            return .unavailable
        }
    }

    /// Ends the session with `/Sessions/Logout`, which revokes its access token on the server.
    public func endSession(_ session: UserSession) async throws {
        try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.reportSessionEnded)
        }
    }
}
