import Foundation
import JellyfinAPI
import PortfolioShared

extension JellyfinServerClient {
    /// The items most recently added to the user's libraries, newest first. New episodes come as their
    /// series.
    ///
    /// - Throws: `JellyfinError.unauthorized` if the server no longer accepts the session,
    ///   `.unreachable` or `.serverError`; `CancellationError` if the task is cancelled.
    public func recentlyAdded(for session: UserSession, limit: Int = 24) async throws -> [MediaItem] {
        let parameters = Paths.GetLatestMediaParameters(
            userID: session.user.id,
            fields: [.overview, .genres, .primaryImageAspectRatio],
            enableImages: true,
            imageTypeLimit: 1,
            enableImageTypes: [.primary, .thumb, .logo, .backdrop],
            enableUserData: true,
            limit: limit
        )
        let items = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.getLatestMedia(parameters: parameters)).value
        }
        return items.compactMap(MediaItem.init)
    }
}
