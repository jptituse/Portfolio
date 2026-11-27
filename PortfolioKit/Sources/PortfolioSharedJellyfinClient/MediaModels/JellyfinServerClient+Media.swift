import Foundation
import JellyfinAPI
import PortfolioShared

extension JellyfinServerClient {
    /// The items most recently added to the user's libraries, or to one of them, newest first. New
    /// episodes come as their series, and a season with new episodes as its show, with
    /// `hasNewSeason`: the server lists the season itself, which has no page of its own here.
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
        return await showsInPlaceOfSeasons(items, session: session)
    }

    /// `items` with each season in place of its show, once, marked as having a new season. The shows
    /// are asked for together; a season whose show the server doesn't give stays as it is.
    private func showsInPlaceOfSeasons(_ items: [BaseItemDto], session: UserSession) async -> [MediaItem] {
        var showIDs: [String] = []
        for item in items where item.type == .season {
            if let show = item.seriesID, !showIDs.contains(show) { showIDs.append(show) }
        }
        var shows: [String: BaseItemDto] = [:]
        if !showIDs.isEmpty {
            var parameters = Paths.GetItemsParameters()
            parameters.userID = session.user.id
            parameters.ids = showIDs
            parameters.fields = Self.cardFields
            parameters.enableImages = true
            parameters.imageTypeLimit = 1
            parameters.enableImageTypes = Self.cardImageTypes
            parameters.enableUserData = true
            let found = try? await perform(.request) {
                try await makeClient(url: session.server.url, accessToken: session.accessToken)
                    .send(Paths.getItems(parameters: parameters)).value
            }
            for show in found?.items ?? [] {
                if let id = show.id { shows[id] = show }
            }
        }
        var listed: Set<String> = []
        return items.compactMap { item in
            if item.type == .season, let id = item.seriesID, let show = shows[id] {
                return listed.insert(id).inserted ? MediaItem(show, hasNewSeason: true) : nil
            }
            guard let id = item.id, listed.insert(id).inserted else { return nil }
            return MediaItem(item)
        }
    }

    /// The items in a collection or playlist, in its order.
    ///
    /// - Throws: as `recentlyAdded(for:in:limit:)`.
    public func items(in parentID: String, for session: UserSession, limit: Int = 24) async throws -> [MediaItem] {
        var parameters = Paths.GetItemsParameters()
        parameters.userID = session.user.id
        parameters.parentID = parentID
        parameters.limit = limit
        parameters.fields = Self.cardFields
        parameters.enableImages = true
        parameters.imageTypeLimit = 1
        parameters.enableImageTypes = Self.cardImageTypes
        parameters.enableUserData = true
        let result = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.getItems(parameters: parameters)).value
        }
        return (result.items ?? []).compactMap(MediaItem.init)
    }

    /// The user's collections, or their playlists, by name.
    ///
    /// - Throws: as `recentlyAdded(for:in:limit:)`.
    public func groupings(_ kind: Grouping, for session: UserSession) async throws -> [MediaItem] {
        var parameters = Paths.GetItemsParameters()
        parameters.userID = session.user.id
        parameters.includeItemTypes = [kind == .collections ? .boxSet : .playlist]
        parameters.isRecursive = true
        parameters.sortBy = [.sortName]
        parameters.sortOrder = [.ascending]
        let result = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.getItems(parameters: parameters)).value
        }
        return (result.items ?? []).compactMap(MediaItem.init)
    }

    /// Items a user groups others in.
    public enum Grouping: Sendable {
        case collections
        case playlists
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
    static let cardFields: [ItemFields] = [.overview, .genres, .primaryImageAspectRatio, .dateCreated]
    /// The images a card shows: poster, thumbnail, logo and backdrop.
    static let cardImageTypes: [ImageType] = [.primary, .thumb, .logo, .backdrop]
}
