import Foundation
import PortfolioShared
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedJellyfinClient

struct JellyfinServerClientTrickplayTests {
    let client = JellyfinServerClient.mocked

    func signIn(to mock: MockJellyfinServer) async throws -> UserSession {
        let server = try await client.validateServer(at: mock.url)
        return try await client.signIn(to: server, username: "alex", password: "hunter2")
    }

    /// Arrival, with pictures 320 and 640 wide: 250 of each, 10 seconds apart.
    func arrival() -> MockJellyfinServer.Item {
        var arrival = MockJellyfinServer.Item(name: "Arrival")
        arrival.trickplay = [.init(width: 320, height: 180, count: 250), .init(width: 640, height: 360, count: 250)]
        return arrival
    }

    @Test func findsThePicturesAtTheSmallestWidthWideEnough() async throws {
        let arrival = arrival()
        let mock = MockJellyfinServer(items: [arrival])
        let session = try await signIn(to: mock)

        let trickplay = try #require(try await client.trickplay(
            for: MediaItem(id: arrival.id, name: "Arrival", kind: .movie),
            versionID: arrival.id,
            pixelWidth: 400,
            session: session
        ))

        #expect(trickplay.pictureWidth == 640)
        #expect(trickplay.pictureHeight == 360)
        #expect(trickplay.columns == 10)
        #expect(trickplay.rows == 10)
        #expect(trickplay.count == 250)
        #expect(trickplay.interval == .seconds(10))
        // 250 pictures, 100 to a tile.
        #expect(trickplay.tileURLs.map(\.path) == (0..<3).map { "/Videos/\(arrival.id)/Trickplay/640/\($0).jpg" })
        #expect(trickplay.tileURLs.allSatisfy { $0.query() == "mediaSourceId=\(arrival.id)" })
        #expect(trickplay.httpHeaders["Authorization"]?.contains("Token=\(session.accessToken)") == true)
    }

    @Test func takesTheWidestWhenNoneIsWideEnough() async throws {
        let arrival = arrival()
        let mock = MockJellyfinServer(items: [arrival])
        let session = try await signIn(to: mock)

        let trickplay = try await client.trickplay(
            for: MediaItem(id: arrival.id, name: "Arrival", kind: .movie),
            versionID: nil,
            pixelWidth: 800,
            session: session
        )

        #expect(trickplay?.pictureWidth == 640)
    }

    @Test func leavesOutTilesTooBigToDecode() async throws {
        var arrival = arrival()
        arrival.trickplay.append(.init(width: 1280, height: 720, count: 250))
        let mock = MockJellyfinServer(items: [arrival])
        let session = try await signIn(to: mock)

        let trickplay = try await client.trickplay(
            for: MediaItem(id: arrival.id, name: "Arrival", kind: .movie),
            versionID: arrival.id,
            pixelWidth: 800,
            session: session
        )

        // A tile of 1280-pixel pictures is 92 million pixels.
        #expect(trickplay?.pictureWidth == 640)
    }

    @Test func findsNoneWhereTheServerMadeNone() async throws {
        let mock = MockJellyfinServer(items: [MockJellyfinServer.Item(name: "Arrival")])
        let session = try await signIn(to: mock)

        let trickplay = try await client.trickplay(
            for: MediaItem(id: mock.items[0].id, name: "Arrival", kind: .movie),
            versionID: mock.items[0].id,
            pixelWidth: 400,
            session: session
        )

        #expect(trickplay == nil)
    }

    @Test func theTilesLoadSignedIn() async throws {
        let arrival = arrival()
        let mock = MockJellyfinServer(items: [arrival])
        let session = try await signIn(to: mock)
        let trickplay = try #require(try await client.trickplay(
            for: MediaItem(id: arrival.id, name: "Arrival", kind: .movie),
            versionID: arrival.id,
            pixelWidth: 320,
            session: session
        ))
        let urlSession = URLSession(configuration: MockJellyfinServer.sessionConfiguration)
        func status(of url: URL, signedIn: Bool) async throws -> Int? {
            var request = URLRequest(url: url)
            if signedIn { request.allHTTPHeaderFields = trickplay.httpHeaders }
            return try await (urlSession.data(for: request).1 as? HTTPURLResponse)?.statusCode
        }

        #expect(try await status(of: trickplay.tileURLs[2], signedIn: true) == 200)
        #expect(try await status(of: trickplay.tileURLs[2], signedIn: false) == 401)
    }
}
