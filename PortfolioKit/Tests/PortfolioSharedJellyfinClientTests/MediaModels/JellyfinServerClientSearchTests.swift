import Foundation
import PortfolioShared
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedJellyfinClient

struct JellyfinServerClientSearchTests {
    let client = JellyfinServerClient.mocked

    func signIn(to mock: MockJellyfinServer) async throws -> UserSession {
        let server = try await client.validateServer(at: mock.url)
        return try await client.signIn(to: server, username: "alex", password: "hunter2")
    }

    /// The query of each `/Items` request the server got.
    func itemQueries(to mock: MockJellyfinServer) -> [[URLQueryItem]] {
        mock.requests.filter { $0.url?.path == "/Items" }.compactMap { request in
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems }
        }
    }

    func types(in query: [URLQueryItem]) -> Set<String> {
        Set(query.filter { $0.name == "includeItemTypes" }.compactMap(\.value))
    }

    /// Arrival's many kinds, with Amy Adams in it.
    func mock() -> MockJellyfinServer {
        var arrival = MockJellyfinServer.Item(name: "Arrival", genres: ["Drama"])
        arrival.people = [.init(name: "Amy Adams", imageTag: "i-amy")]
        return MockJellyfinServer(items: [
            arrival,
            MockJellyfinServer.Item(name: "Arrival 2", genres: ["Comedy"]),
            MockJellyfinServer.Item(name: "Dune"),
            MockJellyfinServer.Item(name: "The Arrival", type: "Series", genres: ["Drama"]),
            MockJellyfinServer.Item(name: "Arrivals and Departures", type: "Episode"),
            MockJellyfinServer.Item(name: "Arrival Collection", type: "BoxSet"),
            MockJellyfinServer.Item(name: "Arrival (Live)", type: "MusicVideo"),
        ])
    }

    @Test func findsTitlesOfEveryKindTogetherWithEpisodesAndPeopleBesides() async throws {
        let mock = mock()
        let session = try await signIn(to: mock)

        let found = try await client.search("arriv", for: session, limit: 30, rowLimit: 12)

        #expect(Set(found.items.map(\.name)) == ["Arrival", "Arrival 2", "The Arrival", "Arrival Collection", "Arrival (Live)"])
        #expect(found.items.first { $0.name == "Arrival (Live)" }?.kind == .musicVideo)
        #expect(found.episodes.map(\.name) == ["Arrivals and Departures"])
        #expect(found.people.isEmpty)
        // Which filters have anything in them, and the genres of what was found.
        #expect(found.kinds == [.movies, .shows, .musicVideos, .collections, .episodes])
        #expect(found.genres == ["Drama", "Comedy"])
        // Asked of the whole server, as the user: the titles together, so the server orders them
        // together, and episodes apart, with what cards show.
        let queries = itemQueries(to: mock)
        #expect(Set(queries.map(types)) == [["Movie", "Series", "MusicVideo", "BoxSet"], ["Episode"]])
        for query in queries {
            #expect(query.contains(URLQueryItem(name: "searchTerm", value: "arriv")))
            #expect(query.contains(URLQueryItem(name: "recursive", value: "true")))
            #expect(query.contains(URLQueryItem(name: "userId", value: session.user.id)))
            #expect(query.contains(URLQueryItem(name: "enableUserData", value: "true")))
        }
        #expect(queries.first { types(in: $0) == ["Episode"] }?.contains(URLQueryItem(name: "limit", value: "12")) == true)
        #expect(queries.first { types(in: $0).contains("Movie") }?.contains(URLQueryItem(name: "limit", value: "30")) == true)
    }

    @Test func checksTheKindsNotAmongAFullTopResults() async throws {
        let mock = mock()
        let session = try await signIn(to: mock)

        // As many as were asked for, all movies: there may be more of other kinds.
        let found = try await client.search("arriv", for: session, limit: 1)

        #expect(found.items.map(\.name) == ["Arrival"])
        #expect(found.kinds == [.movies, .shows, .musicVideos, .collections, .episodes])
        let checks = itemQueries(to: mock).filter { $0.contains(URLQueryItem(name: "limit", value: "1")) }
        #expect(Set(checks.map(types)) == [["Movie", "Series", "MusicVideo", "BoxSet"], ["Series"], ["MusicVideo"], ["BoxSet"]])
    }

    @Test func doesntCheckTheKindsWhenTopResultsHasRoom() async throws {
        let mock = mock()
        let session = try await signIn(to: mock)

        let found = try await client.search("arrival 2", for: session)

        #expect(found.kinds == [.movies])
        #expect(itemQueries(to: mock).count == 2, "Only the titles and episodes should be asked")
    }

    @Test(arguments: [
        (SearchFilter.movies, ["Arrival", "Arrival 2"]),
        (.shows, ["The Arrival"]),
        (.musicVideos, ["Arrival (Live)"]),
        (.collections, ["Arrival Collection"]),
        (.episodes, ["Arrivals and Departures"]),
    ])
    func findsOneKind(_ filter: SearchFilter, names: [String]) async throws {
        let mock = mock()
        let session = try await signIn(to: mock)

        let found = try await client.search("arriv", in: filter, for: session)

        #expect(Set(found.items.map(\.name)) == Set(names))
        #expect(found.episodes.isEmpty)
        #expect(found.people.isEmpty)
        #expect(itemQueries(to: mock).count == 1, "A kind should be asked for alone")
    }

    @Test func findsTitlesInAGenre() async throws {
        let mock = mock()
        let session = try await signIn(to: mock)

        let drama = Genre(id: MockJellyfinServer.genreID("Drama"), name: "Drama")
        let found = try await client.search("arriv", in: .genre(drama), for: session)

        #expect(Set(found.items.map(\.name)) == ["Arrival", "The Arrival"])
        let query = try #require(itemQueries(to: mock).first)
        #expect(query.contains(URLQueryItem(name: "genreIds", value: drama.id)))
        #expect(types(in: query) == ["Movie", "Series", "MusicVideo", "BoxSet"])
    }

    @Test func listsTheGenresOfWhatsSearched() async throws {
        let mock = mock()
        let session = try await signIn(to: mock)

        let genres = try await client.searchGenres(for: session)

        #expect(genres.map(\.name) == ["Comedy", "Drama"])
        let query = URLComponents(url: try #require(mock.requests.last?.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(types(in: query) == ["Movie", "Series", "MusicVideo", "BoxSet"])
    }

    @Test func findsPeopleByNameWithTheirPictures() async throws {
        let mock = mock()
        let session = try await signIn(to: mock)

        let found = try await client.search("adams", for: session)

        #expect(found.people == [Person(id: mock.items[0].people[0].id, name: "Amy Adams", imageTag: "i-amy")])
        let query = URLComponents(url: try #require(mock.requests.last { $0.url?.path == "/Persons" }?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.contains(URLQueryItem(name: "searchTerm", value: "adams")) == true)
        #expect(query?.contains(URLQueryItem(name: "userId", value: session.user.id)) == true)
    }

    @Test func findsOnlyPeopleForPeople() async throws {
        let mock = mock()
        let session = try await signIn(to: mock)

        let found = try await client.search("a", in: .people, for: session)

        #expect(found.people.map(\.name) == ["Amy Adams"])
        #expect(found.items.isEmpty)
        #expect(itemQueries(to: mock).isEmpty)
    }

    @Test func putsPeopleWhoseNamesMatchBestFirst() {
        let people = ["Atom Egoyan", "Tomas Alfredson", "Mark Tomlinson", "Tom Hanks", "Tom", "Tom Hardy", "Rotomi Okafor"]
            .enumerated().map { Person(id: "\($0.offset)", name: $0.element) }

        let ranked = JellyfinServerClient.byRelevance(people, to: "tom").map(\.name)

        // Their name, then starting with it as a word, then starting with it, then a later word starting
        // with it, then the rest, each as the server listed them.
        #expect(ranked == ["Tom", "Tom Hanks", "Tom Hardy", "Tomas Alfredson", "Mark Tomlinson", "Atom Egoyan", "Rotomi Okafor"])
    }

    @Test func matchesPeopleIgnoringCaseAccentsAndSpaces() {
        let people = [Person(id: "1", name: "Penélope  Cruz"), Person(id: "2", name: "Penelope Ann Miller")]

        #expect(JellyfinServerClient.byRelevance(people, to: " PENELOPE cruz").map(\.id) == ["1", "2"])
    }

    @Test func keepsAsManyPeopleAsItsLimit() async throws {
        var crowded = MockJellyfinServer.Item(name: "Crowded")
        crowded.people = (1...30).map { .init(name: "Extra \($0)") }
        let mock = MockJellyfinServer(items: [crowded])
        let session = try await signIn(to: mock)

        let found = try await client.search("extra", for: session, rowLimit: 10)

        #expect(found.people.count == 10)
        let query = URLComponents(url: try #require(mock.requests.last { $0.url?.path == "/Persons" }?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.contains(URLQueryItem(name: "limit", value: "\(JellyfinServerClient.peopleSearched)")) == true)
    }

    @Test func findsNothingWhereNothingMatches() async throws {
        let mock = mock()
        let session = try await signIn(to: mock)

        #expect(try await client.search("zzz", for: session).isEmpty)
    }
}
