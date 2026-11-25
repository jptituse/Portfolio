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
        #expect(source.method == .directPlay)
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

    @Test func asksForTheFileAsItIsAndForAStreamTheServerMakesOtherwise() async throws {
        let mock = MockJellyfinServer(items: [arrival])
        let session = try await signIn(to: mock)

        _ = try await client.playbackSource(for: item(arrival), session: session)

        let body = try #require(mock.playbackInfoRequests.last)
        let request = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(request["EnableDirectPlay"] as? Bool == true)
        #expect(request["EnableTranscoding"] as? Bool == true)
        #expect(request["MaxStreamingBitrate"] as? Int == 400_000_000)
        #expect(request["UserId"] as? String == session.user.id)
        // The server picks the tracks for the user.
        #expect(request["AudioStreamIndex"] == nil)
        #expect(request["SubtitleStreamIndex"] == nil)
        let profile = try #require(request["DeviceProfile"] as? [String: Any])
        let directPlay = try #require((profile["DirectPlayProfiles"] as? [[String: Any]])?.first)
        #expect((directPlay["Container"] as? String)?.split(separator: ",").contains("mkv") == true)
        #expect((directPlay["VideoCodec"] as? String)?.split(separator: ",").contains("hevc") == true)
        #expect((directPlay["AudioCodec"] as? String)?.split(separator: ",").contains("truehd") == true)
        let transcoding = try #require((profile["TranscodingProfiles"] as? [[String: Any]])?.first)
        #expect(transcoding["Protocol"] as? String == "hls")
        #expect(transcoding["Container"] as? String == "mp4")
        #expect(transcoding["VideoCodec"] as? String == "hevc,h264")
        let subtitles = try #require(profile["SubtitleProfiles"] as? [[String: Any]])
        #expect(subtitles.contains { $0["Format"] as? String == "pgssub" && $0["Method"] as? String == "Embed" })
        #expect(subtitles.contains { $0["Format"] as? String == "srt" && $0["Method"] as? String == "External" })
    }

    @Test func asksForTheVersionTracksAndBitrateRequested() async throws {
        let mock = MockJellyfinServer(items: [arrival])
        let session = try await signIn(to: mock)
        let asked = PlaybackRequest(versionID: arrival.id, audioTrack: 4, subtitles: .track(5), maxBitrate: 8_000_000, startPosition: .seconds(600))

        _ = try await client.playbackSource(for: item(arrival), asked, session: session)

        let body = try #require(mock.playbackInfoRequests.last)
        let request = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(request["MediaSourceId"] as? String == arrival.id)
        #expect(request["AudioStreamIndex"] as? Int == 4)
        #expect(request["SubtitleStreamIndex"] as? Int == 5)
        #expect(request["MaxStreamingBitrate"] as? Int == 8_000_000)
        #expect(request["StartTimeTicks"] as? Int == 6_000_000_000)
    }

    @Test func asksForNoSubtitlesAsJellyfinNumbersThem() async throws {
        let mock = MockJellyfinServer(items: [arrival])
        let session = try await signIn(to: mock)

        _ = try await client.playbackSource(for: item(arrival), PlaybackRequest(subtitles: .off), session: session)

        let body = try #require(mock.playbackInfoRequests.last)
        let request = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(request["SubtitleStreamIndex"] as? Int == -1)
    }

    @Test func listsTheVersionsTracksAsTheyPlayAsItIs() async throws {
        let mock = MockJellyfinServer(items: [arrival])
        let session = try await signIn(to: mock)

        let source = try await client.playbackSource(for: item(arrival), session: session)

        #expect(source.audioTracks.map(\.id) == [3, 4])
        #expect(source.audioTracks.map(\.title) == ["English - Dolby Digital+ - 5.1 - Default", "Spanish - AAC - Stereo"])
        #expect(source.audioTracks.map(\.language) == ["eng", "spa"])
        #expect(source.audioTrack == 3)
        #expect(source.bitrate == 20_000_000)
        #expect(source.subtitleTracks.map(\.id) == [0, 1, 5, 6])
        #expect(source.subtitleTracks.map(\.isText) == [true, false, true, false])
        #expect(source.subtitleTrack == nil)
        let deliveries = source.subtitleTracks.map(\.delivery)
        // A text file of its own, fetched from the server; pictures in a file of their own, drawn into a
        // stream by it; those in the file, read from it.
        guard case .file(let url) = deliveries[0] else {
            Issue.record("Expected a subtitle file, got \(deliveries[0])")
            return
        }
        #expect(url.host() == mock.url.host())
        #expect(url.path() == "/Videos/\(arrival.id)/\(arrival.id)/Subtitles/0/0/Stream.srt")
        #expect(Array(deliveries[1...]) == [.transcoded, .inStream, .inStream])
    }

    @Test func startsOnTheTracksTheServerPicks() async throws {
        var spanish = arrival
        spanish.defaultAudioStream = 4
        spanish.defaultSubtitleStream = 5
        let mock = MockJellyfinServer(items: [spanish])
        let session = try await signIn(to: mock)

        let source = try await client.playbackSource(for: item(spanish), session: session)

        #expect(source.audioTrack == 4)
        #expect(source.subtitleTrack == 5)
    }

    @Test func playsTheServersStreamWhenItWontSendTheFileAsItIs() async throws {
        var item = arrival
        item.isDirectlyPlayable = false
        let mock = MockJellyfinServer(items: [item])
        let session = try await signIn(to: mock)

        let source = try await client.playbackSource(for: self.item(item), session: session)

        let components = try #require(URLComponents(url: source.url, resolvingAgainstBaseURL: false))
        #expect(source.method == .transcode)
        #expect(source.url.host() == mock.url.host())
        #expect(components.path == "/videos/\(item.id)/master.m3u8")
        #expect(components.queryItems?.contains(URLQueryItem(name: "PlaySessionId", value: source.playSessionID)) == true)
        #expect(source.httpHeaders["Authorization"]?.contains("Token=\(session.accessToken)") == true)
        // Text subtitles in the file come from the server as files of their own; pictures it draws in.
        #expect(source.subtitleTracks.map(\.isFile) == [true, false, true, false])
        #expect(source.subtitleTracks[3].delivery == .transcoded)
    }

    @Test func playsTheFileAsItIsAskedForTheOriginalWhereTheServerWouldMakeAStream() async throws {
        var item = arrival
        item.isDirectlyPlayable = false
        // The picture file, which only a stream it makes could carry.
        item.defaultSubtitleStream = 1
        let mock = MockJellyfinServer(items: [item])
        let session = try await signIn(to: mock)

        let source = try await client.playbackSource(for: self.item(item), PlaybackRequest(playsOriginal: true), session: session)

        let components = try #require(URLComponents(url: source.url, resolvingAgainstBaseURL: false))
        #expect(source.method == .directPlay)
        #expect(components.path == "/Videos/\(item.id)/stream")
        #expect(components.queryItems?.contains(URLQueryItem(name: "static", value: "true")) == true)
        // The file's own tracks: subtitles in it read from it, and a text file of its own fetched, but not
        // pictures in a file of their own.
        #expect(source.subtitleTracks.map(\.id) == [0, 5, 6])
        #expect(source.subtitleTracks.map(\.isFile) == [true, false, false])
        #expect(source.subtitleTracks[1...].map(\.delivery) == [.inStream, .inStream])
        #expect(source.subtitleTrack == nil)
        #expect(source.audioTrack == 3)
    }

    @Test func playsTheServersStreamAtALowerBitrate() async throws {
        let mock = MockJellyfinServer(items: [arrival])
        let session = try await signIn(to: mock)

        let source = try await client.playbackSource(for: item(arrival), PlaybackRequest(maxBitrate: 8_000_000), session: session)

        let components = try #require(URLComponents(url: source.url, resolvingAgainstBaseURL: false))
        #expect(source.method == .transcode)
        #expect(components.queryItems?.contains(URLQueryItem(name: "VideoBitrate", value: "8000000")) == true)
        // The file's bitrate, for the qualities still to offer.
        #expect(source.bitrate == 20_000_000)
    }

    @Test func eachSourceIsAPlaySessionOfItsOwn() async throws {
        let mock = MockJellyfinServer(items: [arrival])
        let session = try await signIn(to: mock)

        let first = try await client.playbackSource(for: item(arrival), session: session)
        let second = try await client.playbackSource(for: item(arrival), PlaybackRequest(maxBitrate: 8_000_000), session: session)

        #expect(first.playSessionID != second.playSessionID)
    }

    @Test func stopsAStreamTheServerMakes() async throws {
        let mock = MockJellyfinServer(items: [arrival])
        let session = try await signIn(to: mock)
        let source = try await client.playbackSource(for: item(arrival), PlaybackRequest(maxBitrate: 8_000_000), session: session)

        try await client.stopTranscoding(source, session: session)

        #expect(mock.stoppedTranscodes == [source.playSessionID])
        let request = try #require(mock.requests.last)
        let query = try #require(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems)
        #expect(query.contains(URLQueryItem(name: "deviceId", value: client.identity.deviceID)))
    }

    @Test func stopsNothingForAFilePlayedAsItIs() async throws {
        let mock = MockJellyfinServer(items: [arrival])
        let session = try await signIn(to: mock)
        let source = try await client.playbackSource(for: item(arrival), session: session)
        let requests = mock.requests.count

        try await client.stopTranscoding(source, session: session)

        #expect(mock.requests.count == requests)
    }

    @Test func keepsTheServersPathInWhatItGives() throws {
        let server = ServerInfo(id: "server", name: "Living Room", version: "10.11.2", url: try #require(URL(string: "https://media.example.com/jellyfin")))

        let url = JellyfinServerClient.url(for: "/videos/1/master.m3u8?ApiKey=token", on: server)

        #expect(url?.absoluteString == "https://media.example.com/jellyfin/videos/1/master.m3u8?ApiKey=token")
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
        #expect(body["AudioStreamIndex"] as? Int == 3)
        // Off, as Jellyfin numbers it.
        #expect(body["SubtitleStreamIndex"] as? Int == -1)
    }

    @Test func reportsTheStreamTheServerMakesAndTheTracksPlaying() async throws {
        let mock = MockJellyfinServer(items: [arrival])
        let session = try await signIn(to: mock)
        var source = try await client.playbackSource(for: item(arrival), PlaybackRequest(maxBitrate: 8_000_000), session: session)
        source.audioTrack = 4
        source.subtitleTrack = 5

        try await client.reportPlaybackProgress(of: item(arrival), from: source, at: .seconds(30), isPaused: false, session: session)

        let report = try #require(mock.playbackReports.last)
        let body = try #require(try JSONSerialization.jsonObject(with: report.body) as? [String: Any])
        #expect(body["PlayMethod"] as? String == "Transcode")
        #expect(body["PlaySessionId"] as? String == source.playSessionID)
        #expect(body["AudioStreamIndex"] as? Int == 4)
        #expect(body["SubtitleStreamIndex"] as? Int == 5)
    }

    @Test func reportsWherePlaybackIsAndWhetherItsPaused() async throws {
        let mock = MockJellyfinServer(items: [arrival])
        let session = try await signIn(to: mock)
        let source = try await client.playbackSource(for: item(arrival), session: session)

        try await client.reportPlaybackProgress(of: item(arrival), from: source, at: .seconds(754), isPaused: true, session: session)

        let report = try #require(mock.playbackReports.last)
        let body = try #require(try JSONSerialization.jsonObject(with: report.body) as? [String: Any])
        #expect(report.kind == .progress)
        #expect(body["ItemId"] as? String == arrival.id)
        #expect(body["MediaSourceId"] as? String == arrival.id)
        #expect(body["PlaySessionId"] as? String == MockJellyfinServer.playSessionID)
        #expect(body["PlayMethod"] as? String == "DirectPlay")
        #expect(body["PositionTicks"] as? Int == 7_540_000_000)
        #expect(body["IsPaused"] as? Bool == true)
    }

    @Test func readsWhereTheUserGotToAsTheServerHasItNow() async throws {
        var watched = arrival
        watched.watchedMinutes = 42
        watched.lastPlayed = Date(timeIntervalSince1970: 1_800_000_000)
        let mock = MockJellyfinServer(items: [watched])
        let session = try await signIn(to: mock)

        let userData = try await client.userData(for: item(watched), session: session)

        #expect(userData.playbackPosition == .seconds(42 * 60))
        #expect(userData.lastPlayed == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(userData.canResume)
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

    @Test func saysWhenTheServerWontSendTheItemEitherWay() async throws {
        var item = arrival
        item.isDirectlyPlayable = false
        item.isTranscodable = false
        let mock = MockJellyfinServer(items: [item])
        let session = try await signIn(to: mock)

        await #expect(throws: JellyfinError.cannotPlay) {
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

private extension MediaTrack {
    var isFile: Bool {
        if case .file = delivery { true } else { false }
    }
}
