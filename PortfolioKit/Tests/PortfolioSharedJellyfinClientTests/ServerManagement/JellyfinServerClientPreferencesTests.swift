import Foundation
import PortfolioShared
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedJellyfinClient

struct JellyfinServerClientPreferencesTests {
    let client = JellyfinServerClient.mocked

    func signIn(to mock: MockJellyfinServer) async throws -> UserSession {
        let server = try await client.validateServer(at: mock.url)
        return try await client.signIn(to: server, username: "alex", password: "hunter2")
    }

    @Test func listsEachLanguageTheServerKnowsOnceByName() async throws {
        let mock = MockJellyfinServer()
        let session = try await signIn(to: mock)

        let languages = try await client.languages(for: session)

        #expect(languages == [
            Language(code: "eng", name: "English"),
            Language(code: "fre", name: "French"),
            Language(code: "spa", name: "Spanish"),
        ])
    }

    @Test func readsTheLanguagesTheAccountPrefers() async throws {
        var account = MockJellyfinServer.Account(name: "alex", password: "hunter2")
        account.audioLanguage = "jpn"
        account.subtitleLanguage = "eng"
        let mock = MockJellyfinServer(accounts: [account])
        let session = try await signIn(to: mock)

        let preferences = try await client.languagePreferences(for: session)

        #expect(preferences == LanguagePreferences(audio: "jpn", subtitle: "eng"))
    }

    @Test func takesAnEmptyLanguagePreferenceAsNone() async throws {
        var account = MockJellyfinServer.Account(name: "alex", password: "hunter2")
        account.audioLanguage = ""
        let mock = MockJellyfinServer(accounts: [account])
        let session = try await signIn(to: mock)

        let preferences = try await client.languagePreferences(for: session)

        #expect(preferences == LanguagePreferences())
    }

    @Test func measuresHowFastTheServerAnswersAndSends() async throws {
        let mock = MockJellyfinServer()
        let session = try await signIn(to: mock)

        let speed = try await client.measureSpeed(of: session.server, session: session, sampleSize: 1_000_000)

        #expect(speed.responseTime > .zero)
        #expect(try #require(speed.bitrate) > 0)
        let sample = try #require(mock.requests.last)
        #expect(sample.url?.path == "/Playback/BitrateTest")
        #expect(sample.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.contains(URLQueryItem(name: "size", value: "1000000")) == true)
    }

    @Test func measuresOnlyHowFastTheServerAnswersWithoutAnAccount() async throws {
        let mock = MockJellyfinServer()
        let server = try await client.validateServer(at: mock.url)

        let speed = try await client.measureSpeed(of: server, session: nil)

        #expect(speed.bitrate == nil)
        #expect(mock.requests.filter { $0.url?.path == "/System/Ping" }.count == 3)
    }

    @Test func failsToMeasureAServerThatIsOffline() async throws {
        let server = ServerInfo(id: "gone", name: "Gone", version: "10.10.0", url: MockJellyfinServer.uniqueURL())

        await #expect(throws: JellyfinError.unreachable) {
            try await client.measureSpeed(of: server, session: nil)
        }
    }

    @Test func listsTheUsersCollectionsAndPlaylistsByName() async throws {
        let mock = MockJellyfinServer(items: [
            .init(name: "Pixar", type: "BoxSet"),
            .init(name: "Arrival"),
            .init(name: "Date Night", type: "Playlist"),
            .init(name: "Alien", type: "BoxSet"),
        ])
        let session = try await signIn(to: mock)

        let collections = try await client.groupings(.collections, for: session)
        let playlists = try await client.groupings(.playlists, for: session)

        #expect(collections.map(\.name) == ["Alien", "Pixar"])
        #expect(playlists.map(\.name) == ["Date Night"])
    }

    @Test func listsTheItemsOfACollection() async throws {
        let pixar = MockJellyfinServer.Item(name: "Pixar", type: "BoxSet")
        let mock = MockJellyfinServer(items: [
            pixar,
            .init(name: "Up", libraryID: pixar.id),
            .init(name: "Arrival"),
            .init(name: "Coco", libraryID: pixar.id),
        ])
        let session = try await signIn(to: mock)

        let items = try await client.items(in: pixar.id, for: session, limit: 8)

        #expect(items.map(\.name) == ["Up", "Coco"])
        let request = try #require(mock.requests.last)
        #expect(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.contains(URLQueryItem(name: "limit", value: "8")) == true)
    }

    // MARK: The account's name and picture

    @Test func renamesTheAccountKeepingWhatElseTheServerHasForIt() async throws {
        let mock = MockJellyfinServer()
        let session = try await signIn(to: mock)

        let renamed = try await client.rename(session, to: "Alex Rivera")

        #expect(renamed.name == "Alex Rivera")
        #expect(renamed.id == session.user.id)
        let update = try #require(mock.requests.first { $0.httpMethod == "POST" && $0.url?.path == "/Users" })
        let saved = try #require(mock.savedUsers.first)
        let body = try #require(try JSONSerialization.jsonObject(with: saved) as? [String: Any])
        // The whole user goes back, its settings included.
        #expect(body["Name"] as? String == "Alex Rivera")
        #expect(body["Configuration"] != nil)
        #expect(update.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.contains(URLQueryItem(name: "userId", value: session.user.id)) == true)
    }

    @Test func setsAndRemovesTheAccountsPicture() async throws {
        let mock = MockJellyfinServer()
        let session = try await signIn(to: mock)
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])

        let withPicture = try await client.setPicture(png, for: session)

        #expect(withPicture.primaryImageTag != nil)
        #expect(mock.uploadedPictures == [png.base64EncodedData()])
        let upload = try #require(mock.requests.first { $0.url?.path == "/UserImage" })
        #expect(upload.value(forHTTPHeaderField: "Content-Type") == "image/png")

        let without = try await client.removePicture(for: session)

        #expect(without.primaryImageTag == nil)
    }

    @Test func aRenameTheServerRefusesSaysSo() async throws {
        let mock = MockJellyfinServer()
        let session = try await signIn(to: mock)
        mock.revokeAllSessions()

        await #expect(throws: JellyfinError.unauthorized) { try await client.rename(session, to: "Alex") }
    }
}
