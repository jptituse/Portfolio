import Foundation
import PortfolioShared
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedJellyfinClient

struct JellyfinServerClientDetailsTests {
    let client = JellyfinServerClient.mocked

    func signIn(to mock: MockJellyfinServer) async throws -> UserSession {
        let server = try await client.validateServer(at: mock.url)
        return try await client.signIn(to: server, username: "alex", password: "hunter2")
    }

    @Test func findsAnItemsCastStudiosAndFileForTheUser() async throws {
        var arrival = MockJellyfinServer.Item(name: "Arrival")
        arrival.people = [
            .init(name: "Amy Adams", role: "Louise Banks", imageTag: "i-amy"),
            .init(name: "Denis Villeneuve", type: "Director"),
        ]
        arrival.studios = ["FilmNation Entertainment"]
        let mock = MockJellyfinServer(items: [arrival])
        let session = try await signIn(to: mock)

        let details = try await client.details(of: MediaItem(id: arrival.id, name: "Arrival", kind: .movie), session: session)

        #expect(details.credits.map(\.name) == ["Amy Adams", "Denis Villeneuve"])
        #expect(details.credits.map(\.kind) == [.actor, .director])
        #expect(details.credits.first?.role == "Louise Banks")
        #expect(details.studios == ["FilmNation Entertainment"])
        #expect(details.version?.container == "mkv")
        #expect(details.version?.audio.map(\.title) == ["English - Dolby Digital+ - 5.1 - Default", "Spanish - AAC - Stereo"])
        #expect(details.version?.subtitles.count == 4)
        let request = try #require(mock.requests.last)
        let query = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(request.url?.path == "/Items/\(arrival.id)")
        #expect(query?.contains(URLQueryItem(name: "userId", value: session.user.id)) == true)
    }

    @Test func findsItemsLikeAnItem() async throws {
        let dune = MockJellyfinServer.Item(name: "Dune")
        let contact = MockJellyfinServer.Item(name: "Contact")
        var arrival = MockJellyfinServer.Item(name: "Arrival")
        arrival.similar = [dune.id, contact.id]
        let mock = MockJellyfinServer(items: [arrival, dune, contact])
        let session = try await signIn(to: mock)

        let similar = try await client.similarItems(to: MediaItem(id: arrival.id, name: "Arrival", kind: .movie), session: session, limit: 12)

        #expect(similar.map(\.name) == ["Dune", "Contact"])
        let query = URLComponents(url: try #require(mock.requests.last?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.contains(URLQueryItem(name: "limit", value: "12")) == true)
        #expect(query?.contains(URLQueryItem(name: "userId", value: session.user.id)) == true)
    }

    @Test func findsEveryEpisodeOfAShowSeasonBySeason() async throws {
        func episode(_ name: String, season: Int, number: Int, of show: String) -> MockJellyfinServer.Item {
            var episode = MockJellyfinServer.Item(name: name, type: "Episode")
            episode.seriesID = show
            episode.seasonNumber = season
            episode.seasonName = "Season \(season)"
            episode.episodeNumber = number
            return episode
        }
        let stick = MockJellyfinServer.Item(name: "Stick", type: "Series")
        let mock = MockJellyfinServer(items: [
            stick,
            episode("Clark the Mark", season: 2, number: 1, of: stick.id),
            episode("Déjà Vu All Over Again", season: 1, number: 2, of: stick.id),
            episode("Sirens in Soft Spikes", season: 1, number: 1, of: stick.id),
            episode("Elsewhere", season: 1, number: 1, of: "another"),
        ])
        let session = try await signIn(to: mock)

        let episodes = try await client.episodes(ofShow: stick.id, session: session)

        #expect(episodes.map(\.name) == ["Sirens in Soft Spikes", "Déjà Vu All Over Again", "Clark the Mark"])
        #expect(episodes.first?.episode?.seasonName == "Season 1")
        // With its file, for its format and languages.
        #expect(episodes.first?.version?.container == "mkv")
        #expect(episodes.first?.version?.audio.count == 2)
        let query = URLComponents(url: try #require(mock.requests.last?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.contains(URLQueryItem(name: "userId", value: session.user.id)) == true)
    }

    @Test func leavesOutAnEpisodeItCantReadRatherThanTheShowsOthers() async throws {
        let stick = MockJellyfinServer.Item(name: "Stick", type: "Series")
        var pilot = MockJellyfinServer.Item(name: "Pilot", type: "Episode")
        pilot.seriesID = stick.id
        pilot.episodeNumber = 1
        // A value newer than the SDK knows.
        var odd = MockJellyfinServer.Item(name: "Odd", type: "Episode")
        odd.seriesID = stick.id
        odd.episodeNumber = 2
        odd.locationType = "Elsewhere"
        var finale = MockJellyfinServer.Item(name: "Finale", type: "Episode")
        finale.seriesID = stick.id
        finale.episodeNumber = 3
        let mock = MockJellyfinServer(items: [stick, pilot, odd, finale])
        let session = try await signIn(to: mock)

        let episodes = try await client.episodes(ofShow: stick.id, session: session)

        #expect(episodes.map(\.name) == ["Pilot", "Finale"])
    }

    @Test func saysWhenTheServerNoLongerAcceptsTheSession() async throws {
        let mock = MockJellyfinServer(items: [MockJellyfinServer.Item(name: "Arrival")])
        let session = try await signIn(to: mock)
        let expired = UserSession(server: session.server, user: session.user, accessToken: "expired")

        await #expect(throws: JellyfinError.unauthorized) {
            try await client.details(of: MediaItem(id: mock.items[0].id, name: "Arrival", kind: .movie), session: expired)
        }
    }
}
