import Foundation
import PortfolioShared
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedJellyfinClient

struct JellyfinServerClientLibrariesTests {
    let client = JellyfinServerClient.mocked
    let movies = MockJellyfinServer.Library(name: "Movies", collectionType: "movies")
    let movies4K = MockJellyfinServer.Library(name: "4K Movies", collectionType: "movies")
    let shows = MockJellyfinServer.Library(name: "Shows", collectionType: "tvshows")

    func signIn(to mock: MockJellyfinServer) async throws -> UserSession {
        let server = try await client.validateServer(at: mock.url)
        return try await client.signIn(to: server, username: "alex", password: "hunter2")
    }

    func lastQuery(of mock: MockJellyfinServer) throws -> [URLQueryItem] {
        try #require(mock.requests.last?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems)
    }

    func mock() -> MockJellyfinServer {
        MockJellyfinServer(libraries: [movies, shows, movies4K], items: [
            .init(name: "Dune", libraryID: movies.id, genres: ["Science Fiction"]),
            .init(name: "Severance", type: "Series", libraryID: shows.id, genres: ["Drama", "Science Fiction"]),
            .init(name: "Arrival", libraryID: movies4K.id, genres: ["Drama", "Science Fiction"]),
            .init(name: "Heat", libraryID: movies.id, genres: ["Crime"]),
        ])
    }

    // MARK: Libraries

    @Test func listsTheUsersLibrariesInTheServersOrder() async throws {
        let mock = mock()
        let libraries = try await client.libraries(for: try await signIn(to: mock))

        #expect(libraries.map(\.name) == ["Movies", "Shows", "4K Movies"])
        #expect(libraries.map(\.kind) == [.movies, .tvShows, .movies])
    }

    // MARK: Items

    @Test func listsEveryItemOfAKindAcrossItsLibrariesByName() async throws {
        let mock = mock()
        let page = try await client.items(.all, in: .kind(.movies), startIndex: 0, limit: 50, for: try await signIn(to: mock))

        #expect(page.items.map(\.name) == ["Arrival", "Dune", "Heat"])
        #expect(page.totalCount == 3)
        let query = try lastQuery(of: mock)
        #expect(query.contains(URLQueryItem(name: "includeItemTypes", value: "Movie")))
        #expect(query.contains(URLQueryItem(name: "recursive", value: "true")))
        #expect(!query.contains { $0.name == "parentId" })
    }

    @Test func listsOneLibrarysItems() async throws {
        let mock = mock()
        let page = try await client.items(.all, in: .library(Library(id: movies.id, name: "Movies", kind: .movies)), startIndex: 0, limit: 50, for: try await signIn(to: mock))

        #expect(page.items.map(\.name) == ["Dune", "Heat"])
        #expect(try lastQuery(of: mock).contains(URLQueryItem(name: "parentId", value: movies.id)))
    }

    @Test func listsWhatWasAddedMostRecentlyFirst() async throws {
        let mock = mock()
        let page = try await client.items(.recentlyAdded, in: .kind(.movies), startIndex: 0, limit: 50, for: try await signIn(to: mock))

        #expect(page.items.map(\.name) == ["Dune", "Arrival", "Heat"])
        let query = try lastQuery(of: mock)
        #expect(query.filter { $0.name == "sortBy" }.map(\.value) == ["DateCreated", "SortName"])
        #expect(query.filter { $0.name == "sortOrder" }.map(\.value) == ["Descending", "Ascending"])
    }

    @Test func listsShowsWithTheNewestEpisodesFirst() async throws {
        let mock = mock()
        _ = try await client.items(.recentlyAdded, in: .kind(.tvShows), startIndex: 0, limit: 50, for: try await signIn(to: mock))

        #expect(try lastQuery(of: mock).first { $0.name == "sortBy" }?.value == "DateLastContentAdded")
    }

    @Test func listsTheItemsInAGenre() async throws {
        let mock = mock()
        let drama = Genre(id: MockJellyfinServer.genreID("Drama"), name: "Drama")
        let page = try await client.items(.genre(drama), in: .kind(.movies), startIndex: 0, limit: 50, for: try await signIn(to: mock))

        #expect(page.items.map(\.name) == ["Arrival"])
    }

    @Test func listsAPageAtATime() async throws {
        let mock = MockJellyfinServer(items: (1...25).map { .init(name: String(format: "Movie %02d", $0)) })
        let session = try await signIn(to: mock)

        let page = try await client.items(.all, in: .kind(.movies), startIndex: 10, limit: 10, for: session)

        #expect(page.items.map(\.name) == (11...20).map { String(format: "Movie %02d", $0) })
        #expect(page.startIndex == 10)
        #expect(page.totalCount == 25)
    }

    @Test func asksForEverythingTheCardsShow() async throws {
        let mock = mock()
        _ = try await client.items(.all, in: .kind(.movies), startIndex: 0, limit: 50, for: try await signIn(to: mock))

        let query = try lastQuery(of: mock)
        #expect(query.filter { $0.name == "enableImageTypes" }.map(\.value) == ["Primary", "Thumb", "Logo", "Backdrop"])
        #expect(query.contains(URLQueryItem(name: "fields", value: "PrimaryImageAspectRatio")))
        #expect(query.contains(URLQueryItem(name: "enableTotalRecordCount", value: "true")))
    }

    // MARK: Genres

    @Test func listsTheGenresOfAKindByName() async throws {
        let mock = mock()
        let genres = try await client.genres(in: .kind(.movies), for: try await signIn(to: mock))

        #expect(genres.map(\.name) == ["Crime", "Drama", "Science Fiction"])
        #expect(genres.first?.id == MockJellyfinServer.genreID("Crime"))
    }

    @Test func listsTheGenresOfOneLibrary() async throws {
        let mock = mock()
        let library = Library(id: shows.id, name: "Shows", kind: .tvShows)
        let genres = try await client.genres(in: .library(library), for: try await signIn(to: mock))

        #expect(genres.map(\.name) == ["Drama", "Science Fiction"])
    }

    // MARK: Item types

    @Test(arguments: [
        (Library.Kind.movies, ["Movie"]),
        (.tvShows, ["Series"]),
        (.collections, ["BoxSet"]),
        (.playlists, ["Playlist"]),
        (.musicVideos, ["MusicVideo"]),
        (.music, ["MusicAlbum"]),
        (.homeVideos, ["Video"]),
        (.mixed, ["Movie", "Series"]),
        (.other("books"), ["Book"]),
    ])
    func browsesEachKindByItsItems(_ kind: Library.Kind, _ types: [String]) {
        #expect(JellyfinServerClient.itemTypes(for: kind)?.map(\.rawValue) == types)
    }

    @Test func listsWhatsDirectlyInALibraryOfAnUnknownKind() async throws {
        let mock = mock()
        let library = Library(id: "folder", name: "Stuff", kind: .other("folders"))
        _ = try await client.items(.all, in: .library(library), startIndex: 0, limit: 50, for: try await signIn(to: mock))

        let query = try lastQuery(of: mock)
        #expect(!query.contains { $0.name == "includeItemTypes" })
        #expect(query.contains(URLQueryItem(name: "recursive", value: "false")))
    }

    @Test func reportsASessionTheServerNoLongerAccepts() async throws {
        let mock = mock()
        let session = try await signIn(to: mock)
        mock.revokeAllSessions()

        await #expect(throws: JellyfinError.unauthorized) { try await client.libraries(for: session) }
    }
}
