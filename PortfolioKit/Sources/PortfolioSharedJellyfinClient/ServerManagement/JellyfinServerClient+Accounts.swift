import Foundation
import JellyfinAPI
import PortfolioShared

extension JellyfinServerClient {
    /// Renames the account. The server saves the whole user it's sent, its settings included, so the
    /// user is fetched first and sent back with only its name changed.
    ///
    /// - Returns: the account as the server has it now.
    /// - Throws: `JellyfinError.unauthorized` if the server doesn't let the account change it, as when
    ///   an administrator turned that off, or no longer accepts the session; `.unreachable` or
    ///   `.serverError`; `CancellationError` if the task is cancelled.
    public func rename(_ session: UserSession, to name: String) async throws -> User {
        let client = makeClient(url: session.server.url, accessToken: session.accessToken)
        var user = try await perform(.request) { try await client.send(Paths.getCurrentUser).value }
        user.name = name
        let changed = user
        _ = try await perform(.request) { try await client.send(Paths.updateUser(userID: session.user.id, changed)) }
        return try await currentUser(session)
    }

    /// Sets the account's picture to a PNG.
    ///
    /// - Returns: the account as the server has it now, with its picture's new tag.
    /// - Throws: as `rename(_:to:)`.
    public func setPicture(_ png: Data, for session: UserSession) async throws -> User {
        // The server takes the image base64-encoded, with its own type.
        var request = Paths.postUserImage(userID: session.user.id, png.base64EncodedData())
        request.headers = ["Content-Type": "image/png"]
        let upload = request
        _ = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken).send(upload)
        }
        return try await currentUser(session)
    }

    /// Removes the account's picture.
    ///
    /// - Returns: the account as the server has it now.
    /// - Throws: as `rename(_:to:)`.
    public func removePicture(for session: UserSession) async throws -> User {
        _ = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.deleteUserImage(userID: session.user.id))
        }
        return try await currentUser(session)
    }

    private func currentUser(_ session: UserSession) async throws -> User {
        let dto = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken).send(Paths.getCurrentUser).value
        }
        guard let user = User(dto) else { throw JellyfinError.serverError(statusCode: nil) }
        return user
    }
}
