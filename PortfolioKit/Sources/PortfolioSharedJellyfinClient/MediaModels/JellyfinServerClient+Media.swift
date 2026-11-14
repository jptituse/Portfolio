import Foundation
import JellyfinAPI
import PortfolioShared

extension JellyfinServerClient {
    /// The items most recently added to the user's libraries, or to one of them, newest first. New
    /// episodes come as their series.
    ///
    /// - Parameter libraryID: the library to look in, or nil for all of them but those the user has
    ///   left out of their latest items.
    /// - Throws: `JellyfinError.unauthorized` if the server no longer accepts the session,
    ///   `.unreachable` or `.serverError`; `CancellationError` if the task is cancelled.
    public func recentlyAdded(for session: UserSession, in libraryID: String? = nil, limit: Int = 24) async throws -> [MediaItem] {
        let parameters = Paths.GetLatestMediaParameters(
            userID: session.user.id,
            parentID: libraryID,
            fields: Self.cardFields,
            enableImages: true,
            imageTypeLimit: 1,
            enableImageTypes: Self.cardImageTypes,
            enableUserData: true,
            limit: limit
        )
        let items = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.getLatestMedia(parameters: parameters)).value
        }
        return items.compactMap(MediaItem.init)
    }

    /// The videos the user stopped partway through, most recently watched first.
    ///
    /// - Throws: as `recentlyAdded(for:in:limit:)`.
    public func resumeItems(for session: UserSession, limit: Int = 24) async throws -> [MediaItem] {
        let parameters = Paths.GetResumeItemsParameters(
            userID: session.user.id,
            limit: limit,
            fields: Self.cardFields,
            mediaTypes: [.video],
            enableUserData: true,
            imageTypeLimit: 1,
            enableImageTypes: Self.cardImageTypes,
            enableImages: true
        )
        let result = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.getResumeItems(parameters: parameters)).value
        }
        return (result.items ?? []).compactMap(MediaItem.init)
    }

    /// The next episode of each show the user is watching, the shows watched most recently first.
    /// Episodes they've started are left out: they're among `resumeItems(for:limit:)`.
    ///
    /// - Throws: as `recentlyAdded(for:in:limit:)`.
    public func nextUp(for session: UserSession, limit: Int = 24) async throws -> [MediaItem] {
        let parameters = Paths.GetNextUpParameters(
            userID: session.user.id,
            limit: limit,
            fields: Self.cardFields,
            enableImages: true,
            imageTypeLimit: 1,
            enableImageTypes: Self.cardImageTypes,
            enableUserData: true,
            enableResumable: false
        )
        let result = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.getNextUp(parameters: parameters)).value
        }
        return (result.items ?? []).compactMap(MediaItem.init)
    }

    /// The libraries the user has left out of their latest items, in Jellyfin's settings.
    ///
    /// - Throws: as `recentlyAdded(for:in:limit:)`.
    public func librariesLeftOutOfLatest(for session: UserSession) async throws -> Set<String> {
        let user = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.getCurrentUser).value
        }
        return Set(user.configuration?.latestItemsExcludes ?? [])
    }

    /// The fields a card shows, beyond those Jellyfin always sends.
    static let cardFields: [ItemFields] = [.overview, .genres, .primaryImageAspectRatio]
    /// The images a card shows: poster, thumbnail, logo and backdrop.
    static let cardImageTypes: [ImageType] = [.primary, .thumb, .logo, .backdrop]
}
