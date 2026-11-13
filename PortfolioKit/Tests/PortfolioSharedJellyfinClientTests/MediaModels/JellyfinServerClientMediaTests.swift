import Foundation
import PortfolioShared
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedJellyfinClient

struct JellyfinServerClientMediaTests {
    let client = JellyfinServerClient.mocked

    func signIn(to mock: MockJellyfinServer) async throws -> UserSession {
        let server = try await client.validateServer(at: mock.url)
        return try await client.signIn(to: server, username: "alex", password: "hunter2")
    }

    @Test func listsTheItemsAddedMostRecentlyWithTheirImages() async throws {
        let mock = MockJellyfinServer(items: [
            .init(name: "Arrival", imageTags: ["Primary": "p1", "Thumb": "t1"], backdropTags: ["b0"], primaryImageAspectRatio: 16.0 / 9),
            .init(name: "Severance", type: "Series"),
        ])
        let session = try await signIn(to: mock)

        let items = try await client.recentlyAdded(for: session)

        #expect(items.map(\.name) == ["Arrival", "Severance"])
        #expect(items.map(\.kind) == [.movie, .series])
        #expect(items[0].images == [.primary: "p1", .thumb: "t1", .backdrop(): "b0"])
        #expect(items[0].primaryImageAspectRatio == 16.0 / 9)
    }

    @Test func asksForTheUsersItemsWithEveryImageTheCardsUse() async throws {
        let mock = MockJellyfinServer()
        let session = try await signIn(to: mock)

        _ = try await client.recentlyAdded(for: session, limit: 12)

        let request = try #require(mock.requests.last)
        let query = try #require(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems)
        #expect(request.url?.path == "/Items/Latest")
        #expect(query.contains(URLQueryItem(name: "userId", value: session.user.id)))
        #expect(query.contains(URLQueryItem(name: "limit", value: "12")))
        // The SDK sends a list as one query item per value.
        #expect(query.filter { $0.name == "enableImageTypes" }.map(\.value) == ["Primary", "Thumb", "Logo", "Backdrop"])
        // The posters' shapes, so the row can lay them out before they load.
        #expect(query.contains(URLQueryItem(name: "fields", value: "PrimaryImageAspectRatio")))
    }

    @Test func limitsHowManyItCanList() async throws {
        let mock = MockJellyfinServer(items: (1...5).map { .init(name: "Movie \($0)") })
        let session = try await signIn(to: mock)

        #expect(try await client.recentlyAdded(for: session, limit: 3).count == 3)
    }

    @Test func reportsASessionTheServerNoLongerAccepts() async throws {
        let mock = MockJellyfinServer()
        let session = try await signIn(to: mock)
        mock.revokeAllSessions()

        await #expect(throws: JellyfinError.unauthorized) { try await client.recentlyAdded(for: session) }
    }

    @Test func reportsAServerItCannotReach() async throws {
        let mock = MockJellyfinServer()
        let session = try await signIn(to: mock)
        let unreachable = UserSession(
            server: ServerInfo(id: session.server.id, name: "Gone", version: "10.11.2", url: MockJellyfinServer.uniqueURL()),
            user: session.user,
            accessToken: session.accessToken
        )

        await #expect(throws: JellyfinError.unreachable) { try await client.recentlyAdded(for: unreachable) }
    }
}
