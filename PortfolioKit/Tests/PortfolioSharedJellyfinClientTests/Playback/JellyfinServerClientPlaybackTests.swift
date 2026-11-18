import Foundation
import PortfolioShared
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedJellyfinClient

struct JellyfinServerClientPlaybackTests {
    let client = JellyfinServerClient.mocked
    let arrival = MockJellyfinServer.Item(name: "Arrival")

    func signIn(to mock: MockJellyfinServer) async throws -> UserSession {
        let server = try await client.validateServer(at: mock.url)
        return try await client.signIn(to: server, username: "alex", password: "hunter2")
    }

    func item(_ item: MockJellyfinServer.Item) -> MediaItem {
        MediaItem(id: item.id, name: item.name, kind: .movie)
    }

    @Test func playsTheDefaultVersionAsItIsFromTheServer() async throws {
        let mock = MockJellyfinServer(items: [arrival])
        let session = try await signIn(to: mock)

        let source = try await client.playbackSource(for: item(arrival), session: session)

        let components = try #require(URLComponents(url: source.url, resolvingAgainstBaseURL: false))
        #expect(source.url.host() == mock.url.host())
        #expect(components.path == "/Videos/\(arrival.id)/stream")
        #expect(components.queryItems?.contains(URLQueryItem(name: "static", value: "true")) == true)
        // The first version the server lists, not the other.
        #expect(components.queryItems?.contains(URLQueryItem(name: "mediaSourceId", value: arrival.id)) == true)
        #expect(components.queryItems?.contains(URLQueryItem(name: "playSessionId", value: MockJellyfinServer.playSessionID)) == true)
    }

    @Test func signsTheStreamInAsTheProfile() async throws {
        let mock = MockJellyfinServer(items: [arrival])
        let session = try await signIn(to: mock)

        let source = try await client.playbackSource(for: item(arrival), session: session)

        let header = try #require(source.httpHeaders["Authorization"])
        #expect(header.hasPrefix("MediaBrowser "))
        #expect(header.contains("Token=\(session.accessToken)"))
        #expect(header.contains("DeviceId=\(client.identity.deviceID)"))
    }

    @Test func asksToPlayItAsItIsWithoutTranscoding() async throws {
        let mock = MockJellyfinServer(items: [arrival])
        let session = try await signIn(to: mock)

        _ = try await client.playbackSource(for: item(arrival), session: session)

        let body = try #require(mock.playbackInfoRequests.last)
        let request = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(request["EnableDirectPlay"] as? Bool == true)
        #expect(request["EnableTranscoding"] as? Bool == false)
        #expect(request["UserId"] as? String == session.user.id)
        let profile = try #require(request["DeviceProfile"] as? [String: Any])
        let directPlay = try #require((profile["DirectPlayProfiles"] as? [[String: Any]])?.first)
        #expect((directPlay["Container"] as? String)?.split(separator: ",").contains("mkv") == true)
        #expect((directPlay["VideoCodec"] as? String)?.split(separator: ",").contains("hevc") == true)
        #expect((directPlay["AudioCodec"] as? String)?.split(separator: ",").contains("truehd") == true)
        #expect((profile["TranscodingProfiles"] as? [Any])?.isEmpty ?? true)
    }

    @Test func namesTheVersionAndPlaySessionForReportingPlayback() async throws {
        let mock = MockJellyfinServer(items: [arrival])
        let session = try await signIn(to: mock)

        let source = try await client.playbackSource(for: item(arrival), session: session)

        #expect(source.versionID == arrival.id)
        #expect(source.playSessionID == MockJellyfinServer.playSessionID)
    }

    @Test func reportsPlaybackStartingAsPlayedAsItIs() async throws {
        let mock = MockJellyfinServer(items: [arrival])
        let session = try await signIn(to: mock)
        let source = try await client.playbackSource(for: item(arrival), session: session)

        try await client.reportPlaybackStarted(of: item(arrival), from: source, at: .seconds(90), session: session)

        let report = try #require(mock.playbackReports.last)
        let body = try #require(try JSONSerialization.jsonObject(with: report.body) as? [String: Any])
        #expect(report.kind == .started)
        #expect(body["ItemId"] as? String == arrival.id)
        #expect(body["MediaSourceId"] as? String == arrival.id)
        #expect(body["PlaySessionId"] as? String == MockJellyfinServer.playSessionID)
        #expect(body["PlayMethod"] as? String == "DirectPlay")
        #expect(body["PositionTicks"] as? Int == 900_000_000)
    }

    @Test func reportsWherePlaybackStopped() async throws {
        let mock = MockJellyfinServer(items: [arrival])
        let session = try await signIn(to: mock)
        let source = try await client.playbackSource(for: item(arrival), session: session)

        try await client.reportPlaybackStopped(of: item(arrival), from: source, at: .milliseconds(61_500), session: session)

        let report = try #require(mock.playbackReports.last)
        let body = try #require(try JSONSerialization.jsonObject(with: report.body) as? [String: Any])
        #expect(report.kind == .stopped)
        #expect(body["ItemId"] as? String == arrival.id)
        #expect(body["PlaySessionId"] as? String == MockJellyfinServer.playSessionID)
        #expect(body["PositionTicks"] as? Int == 615_000_000)
    }

    @Test func saysWhenTheServerWontSendTheItemAsItIs() async throws {
        var item = arrival
        item.isDirectlyPlayable = false
        let mock = MockJellyfinServer(items: [item])
        let session = try await signIn(to: mock)

        await #expect(throws: JellyfinError.cannotPlayDirectly) {
            try await client.playbackSource(for: self.item(item), session: session)
        }
    }

    @Test func saysWhenTheServerNoLongerAcceptsTheSession() async throws {
        let mock = MockJellyfinServer(items: [arrival])
        let session = try await signIn(to: mock)
        mock.revokeAllSessions()

        await #expect(throws: JellyfinError.unauthorized) {
            try await client.playbackSource(for: item(arrival), session: session)
        }
    }
}
