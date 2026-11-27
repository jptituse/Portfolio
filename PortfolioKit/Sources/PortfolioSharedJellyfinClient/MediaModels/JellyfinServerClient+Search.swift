import Foundation
import JellyfinAPI
import PortfolioShared

extension JellyfinServerClient {
    /// What on the user's server matches `term` in `filter`, by title, or for people by name, as
    /// Jellyfin's own search finds it, asked all at once. Only what the user can see is found.
    ///
    /// - Top Results: up to `limit` movies, shows, music videos and collections together, and up to
    ///   `rowLimit` episodes and people besides.
    /// - A kind: up to `limit` of it.
    /// - A genre: up to `limit` movies, shows, music videos and collections in it.
    ///
    /// The server puts the items whose titles match best first, from 10.10 on: the title itself, then
    /// titles starting with it as a word, then titles starting with it. It lists people by name, so
    /// they're put in the same order here, from more of them than are kept.
    ///
    /// - Throws: as `recentlyAdded(for:in:limit:)`.
    public func search(
        _ term: String,
        in filter: SearchFilter = .topResults,
        for session: UserSession,
        limit: Int = 60,
        rowLimit: Int = 24
    ) async throws -> SearchResults {
        switch filter {
        case .topResults:
            async let titles = items(matching: term, of: Self.searchedMedia, limit: limit, session: session)
            async let episodes = items(matching: term, of: [.episode], limit: rowLimit, session: session)
            async let someone = people(matching: term, limit: rowLimit, session: session)
            let (found, foundEpisodes, foundPeople) = try await (titles, episodes, someone)
            var kinds = Set(found.compactMap { Self.filter(for: $0.kind) })
            // As many as were asked for: there may be more, and a kind not among them may have some.
            if found.count >= limit {
                kinds.formUnion(try await kindsFound(matching: term, among: Self.titleFilters.filter { !kinds.contains($0) }, session: session))
            }
            if !foundEpisodes.isEmpty { kinds.insert(.episodes) }
            if !foundPeople.isEmpty { kinds.insert(.people) }
            return SearchResults(
                items: found,
                episodes: foundEpisodes,
                people: foundPeople,
                kinds: kinds,
                genres: Set(found.flatMap(\.genres))
            )
        case .movies, .shows, .musicVideos, .collections, .episodes:
            return try await SearchResults(items: items(matching: term, of: Self.itemTypes(for: filter), limit: limit, session: session))
        case .people:
            return try await SearchResults(people: people(matching: term, limit: limit, session: session))
        case .genre(let genre):
            return try await SearchResults(items: items(matching: term, of: Self.searchedMedia, in: genre, limit: limit, session: session))
        }
    }

    /// The genres of the movies, shows and music videos the user can see, by name, for Search to filter
    /// by.
    ///
    /// - Throws: as `recentlyAdded(for:in:limit:)`.
    public func searchGenres(for session: UserSession) async throws -> [Genre] {
        let parameters = Paths.GetGenresParameters(
            includeItemTypes: Self.searchedMedia,
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

    /// What Top Results and a genre find together: whole titles, not their episodes.
    static let searchedMedia: [BaseItemKind] = [.movie, .series, .musicVideo, .boxSet]

    /// The item types a kind's filter finds.
    static func itemTypes(for filter: SearchFilter) -> [BaseItemKind] {
        switch filter {
        case .movies: [.movie]
        case .shows: [.series]
        case .musicVideos: [.musicVideo]
        case .collections: [.boxSet]
        case .episodes: [.episode]
        case .topResults, .people, .genre: searchedMedia
        }
    }

    /// The filters of the kinds Top Results finds together.
    static let titleFilters: [SearchFilter] = [.movies, .shows, .musicVideos, .collections]

    /// The filter of an item's kind, among Top Results' titles.
    static func filter(for kind: MediaItem.Kind) -> SearchFilter? {
        switch kind {
        case .movie: .movies
        case .series: .shows
        case .musicVideo: .musicVideos
        case .boxSet: .collections
        default: nil
        }
    }

    /// Which of `filters` find anything matching `term`, each asked for one item, all at once.
    private func kindsFound(matching term: String, among filters: [SearchFilter], session: UserSession) async throws -> Set<SearchFilter> {
        try await withThrowingTaskGroup(of: SearchFilter?.self) { group in
            for filter in filters {
                group.addTask {
                    try await self.items(matching: term, of: Self.itemTypes(for: filter), limit: 1, session: session).isEmpty ? nil : filter
                }
            }
            var found: Set<SearchFilter> = []
            for try await filter in group {
                if let filter { found.insert(filter) }
            }
            return found
        }
    }

    /// The items of `types` whose titles match `term`, in `genre` if there's one, the best first.
    private func items(
        matching term: String,
        of types: [BaseItemKind],
        in genre: Genre? = nil,
        limit: Int,
        session: UserSession
    ) async throws -> [MediaItem] {
        var parameters = Paths.GetItemsParameters()
        parameters.userID = session.user.id
        parameters.searchTerm = term
        parameters.includeItemTypes = types
        parameters.genreIDs = genre.map { [$0.id] }
        parameters.isRecursive = true
        parameters.limit = limit
        // Among titles that match as well.
        parameters.sortBy = [.sortName]
        parameters.sortOrder = [.ascending]
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

    /// Up to `limit` people whose names contain `term`, the best first, from as many as
    /// `peopleSearched` by name.
    private func people(matching term: String, limit: Int, session: UserSession) async throws -> [Person] {
        let parameters = Paths.GetPersonsParameters(
            limit: Self.peopleSearched,
            searchTerm: term,
            imageTypeLimit: 1,
            enableImageTypes: [.primary],
            userID: session.user.id,
            enableImages: true
        )
        let result = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.getPersons(parameters: parameters)).value
        }
        return Array(Self.byRelevance((result.items ?? []).compactMap(Person.init), to: term).prefix(limit))
    }

    /// `people` in the order the server puts items for a search: whose name is `term`, then whose name
    /// starts with it as a word, then starts with it, then has a later word starting with it ("hanks"
    /// for Tom Hanks), then the rest, each in the order they came, ignoring case, accents and extra
    /// spaces.
    static func byRelevance(_ people: [Person], to term: String) -> [Person] {
        let term = searchable(term)
        func rank(_ name: String) -> Int {
            let name = searchable(name)
            if name == term { return 0 }
            if name.hasPrefix(term + " ") { return 1 }
            if name.hasPrefix(term) { return 2 }
            if name.split(separator: " ").contains(where: { $0.hasPrefix(term) }) { return 3 }
            return 4
        }
        return people.enumerated()
            .map { (rank: rank($0.element.name), order: $0.offset, person: $0.element) }
            .sorted { ($0.rank, $0.order) < ($1.rank, $1.order) }
            .map(\.person)
    }

    /// `text` as it's compared: lowercased, without accents, its words separated by single spaces.
    private static func searchable(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// How many people a search asks for, to put the best first: the server lists them by name, and the
    /// best may not be among the first.
    static let peopleSearched = 100
}
