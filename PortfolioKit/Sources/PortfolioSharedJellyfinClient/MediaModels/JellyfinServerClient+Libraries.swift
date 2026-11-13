import Foundation
import JellyfinAPI
import PortfolioShared

extension JellyfinServerClient {
    /// The user's libraries, in the order the server lists them.
    ///
    /// - Throws: `JellyfinError.unauthorized` if the server no longer accepts the session,
    ///   `.unreachable` or `.serverError`; `CancellationError` if the task is cancelled.
    public func libraries(for session: UserSession) async throws -> [Library] {
        let parameters = Paths.GetUserViewsParameters(userID: session.user.id)
        let result = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.getUserViews(parameters: parameters)).value
        }
        return (result.items ?? []).compactMap(Library.init)
    }

    /// The genres of the items in `scope`, by name.
    ///
    /// - Throws: as `libraries(for:)`.
    public func genres(in scope: LibraryScope, for session: UserSession) async throws -> [Genre] {
        let query = Self.query(for: scope)
        let parameters = Paths.GetGenresParameters(
            parentID: query.parentID,
            includeItemTypes: query.itemTypes,
            userID: session.user.id,
            sortBy: [.sortName],
            sortOrder: [.ascending]
        )
        let result = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.getGenres(parameters: parameters)).value
        }
        return (result.items ?? []).compactMap { dto in
            guard let id = dto.id, let name = dto.name else { return nil }
            return Genre(id: id, name: name)
        }
    }

    /// Part of `sidebarItem` in `scope`: up to `limit` items from `startIndex`, and how many there are in all.
    ///
    /// - Throws: as `libraries(for:)`.
    public func items(
        _ sidebarItem: LibrarySidebarItem,
        in scope: LibraryScope,
        startIndex: Int,
        limit: Int,
        for session: UserSession
    ) async throws -> MediaItemPage {
        let query = Self.query(for: scope)
        var parameters = Paths.GetItemsParameters()
        parameters.userID = session.user.id
        parameters.parentID = query.parentID
        parameters.includeItemTypes = query.itemTypes
        parameters.isRecursive = query.itemTypes != nil
        parameters.startIndex = startIndex
        parameters.limit = limit
        parameters.enableTotalRecordCount = true
        parameters.fields = [.overview, .genres, .primaryImageAspectRatio]
        parameters.enableImages = true
        parameters.imageTypeLimit = 1
        parameters.enableImageTypes = [.primary, .thumb, .logo, .backdrop]
        parameters.enableUserData = true
        switch sidebarItem {
        case .recentlyAdded:
            // A show counts as added when its newest episode was.
            parameters.sortBy = query.itemTypes == [.series] ? [.dateLastContentAdded, .sortName] : [.dateCreated, .sortName]
            parameters.sortOrder = [.descending, .ascending]
        case .all:
            parameters.sortBy = [.sortName]
            parameters.sortOrder = [.ascending]
        case .genre(let genre):
            parameters.genreIDs = [genre.id]
            parameters.sortBy = [.sortName]
            parameters.sortOrder = [.ascending]
        }
        let result = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.getItems(parameters: parameters)).value
        }
        let items = (result.items ?? []).compactMap(MediaItem.init)
        return MediaItemPage(items: items, startIndex: startIndex, totalCount: result.totalRecordCount ?? items.count)
    }

    /// Where a scope's items are: its library, if it's one, and the item types it lists. A library of a
    /// kind no type is known for lists what's directly in it.
    static func query(for scope: LibraryScope) -> (parentID: String?, itemTypes: [BaseItemKind]?) {
        switch scope {
        case .library(let library): (library.id, itemTypes(for: library.kind))
        case .kind(let kind): (nil, itemTypes(for: kind))
        }
    }

    /// The item types a kind of library is browsed by: its movies, its shows (not their episodes), and so
    /// on.
    static func itemTypes(for kind: Library.Kind) -> [BaseItemKind]? {
        switch kind {
        case .movies: [.movie]
        case .tvShows: [.series]
        case .collections: [.boxSet]
        case .playlists: [.playlist]
        case .musicVideos: [.musicVideo]
        case .music: [.musicAlbum]
        case .homeVideos: [.video]
        case .liveTV: [.tvChannel]
        case .mixed: [.movie, .series]
        case .other(CollectionType.books.rawValue): [.book]
        case .other(CollectionType.photos.rawValue): [.photo]
        case .other: nil
        }
    }
}
