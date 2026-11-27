import Foundation
import PortfolioShared
import PortfolioSharedJellyfinClient
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedUI

@MainActor
struct CurrentProfileViewModelTests {
    let sessionManager = SessionManager(store: MediaServerStore(storage: InMemorySecureStorage()), authority: JellyfinServerClient.mocked)
    let viewModel: CurrentProfileViewModel

    init() {
        viewModel = CurrentProfileViewModel(client: .mocked, sessionManager: sessionManager, devicePreferences: DevicePreferences(defaults: .forTesting()))
    }

    @Test func showsWhoIsSignedInAndOnWhichServer() throws {
        let alex = User(id: "alex", name: "Alex Rivera", serverID: "server-1", primaryImageTag: "avatar")
        let session = UserSession(server: .sample(), user: alex, accessToken: "token")
        try sessionManager.signIn(session)

        let tile = try #require(viewModel.tile)

        #expect(tile.name == "Alex Rivera")
        #expect(tile.detail == "Living Room")
        #expect(tile.initials == "AR")
        #expect(tile.pictureURL == JellyfinServerClient.mocked.pictureURL(for: alex, on: .sample()))
    }

    @Test func showsNobodyWithoutAnOpenProfile() {
        #expect(viewModel.tile == nil)
    }

    @Test func switchingGoesBackToThePickerAndStaysSignedIn() throws {
        try sessionManager.signIn(.sample())

        viewModel.switchProfile()

        #expect(sessionManager.state == .choosingProfile)
        #expect(sessionManager.servers.first?.isSignedIn("user-1") == true)
        #expect(viewModel.tile == nil)
    }

    @Test func makesAHomeWithArtworkFromTheProfilesServer() throws {
        try sessionManager.signIn(.sample())

        let home = viewModel.makeHomeViewModel()

        #expect((home.images as? JellyfinImageResolver)?.server == .sample())
    }

    // MARK: Item pages

    func signedIn(to mock: MockJellyfinServer) async throws -> CurrentProfileViewModel {
        let client = JellyfinServerClient.mocked
        let sessionManager = SessionManager(store: MediaServerStore(storage: InMemorySecureStorage()), authority: client)
        let server = try await client.validateServer(at: mock.url)
        try sessionManager.signIn(try await client.signIn(to: server, username: "alex", password: "hunter2"))
        return CurrentProfileViewModel(client: client, sessionManager: sessionManager, devicePreferences: DevicePreferences(defaults: .forTesting()), defaults: .forTesting())
    }

    @Test func preparesAFullScreenCardsBadgesAndOpensItsPageOnThemWithoutAskingAgain() async throws {
        let dune = MockJellyfinServer.Item(name: "Dune")
        var arrival = MockJellyfinServer.Item(name: "Arrival")
        arrival.people = [.init(name: "Amy Adams", role: "Louise Banks")]
        arrival.similar = [dune.id]
        let mock = MockJellyfinServer(items: [arrival, dune])
        let profile = try await signedIn(to: mock)
        let card = MediaCardViewModel(item: MediaItem(id: arrival.id, name: "Arrival", kind: .movie))

        profile.prepareDetails(for: card)
        await waitUntil { !card.detailInfo.credits.isEmpty }
        let asked = mock.requests.count { $0.url?.path.hasPrefix("/Items/\(arrival.id)") == true }

        // The test server's file says nothing of its picture's size or its audio's channels, only that it
        // has subtitles.
        #expect(card.detailInfo.badges == ["CC"])
        #expect(card.detailInfo.credits == [.init(label: "Starring", names: "Amy Adams")])
        let page = profile.makeDetail(for: card)
        #expect(page.people.map(\.name) == ["Amy Adams"])
        await waitUntil { !page.similar.isEmpty }
        await page.load()
        #expect(page.similar.map(\.item.name) == ["Dune"])
        #expect(mock.requests.count { $0.url?.path.hasPrefix("/Items/\(arrival.id)") == true } == asked)
    }

    // MARK: Shows

    func episode(_ number: Int, of show: MockJellyfinServer.Item, watched: Int = 0, played: Bool = false, lastPlayed: TimeInterval? = nil) -> MockJellyfinServer.Item {
        var episode = MockJellyfinServer.Item(name: "Episode \(number)", type: "Episode")
        episode.seriesID = show.id
        episode.seasonNumber = 1
        episode.episodeNumber = number
        episode.runtimeMinutes = 45
        episode.watchedMinutes = watched
        episode.isPlayed = played
        episode.lastPlayed = lastPlayed.map(Date.init(timeIntervalSince1970:))
        return episode
    }

    @Test func playsAShowFromWhereTheUserIsInIt() async throws {
        let stick = MockJellyfinServer.Item(name: "Stick", type: "Series")
        let mock = MockJellyfinServer(items: [
            stick,
            episode(1, of: stick, played: true, lastPlayed: 100),
            episode(2, of: stick, watched: 20, lastPlayed: 200),
            episode(3, of: stick),
        ])
        let profile = try await signedIn(to: mock)
        let show = MediaItem(id: stick.id, name: "Stick", kind: .series)

        // Partway through the second: resumed.
        let next = try #require(await profile.nextEpisode(ofShow: show))
        #expect(next.episode.name == "Episode 2")
        #expect(next.start == .resuming)

        // Played to the end here since: the third, from the beginning.
        profile.userDataUpdates.update(UserData(isPlayed: true, lastPlayed: Date(timeIntervalSince1970: 300)), for: next.episode.id)
        let after = try #require(await profile.nextEpisode(ofShow: show))
        #expect(after.episode.name == "Episode 3")
        #expect(after.start == .beginning)
    }

    @Test func describesAShowsNextEpisodeOnItsCard() async throws {
        let stick = MockJellyfinServer.Item(name: "Stick", type: "Series")
        let mock = MockJellyfinServer(items: [
            stick,
            episode(1, of: stick, played: true, lastPlayed: 100),
            episode(2, of: stick),
        ])
        let profile = try await signedIn(to: mock)
        let card = MediaCardViewModel(item: MediaItem(id: stick.id, name: "Stick", kind: .series))

        profile.prepareDetails(for: card)

        await waitUntil { card.detailInfo.episodeLead != nil }
        #expect(card.detailInfo.episodeLead == "S1, E2 · Episode 2")
    }

    @Test func asksAShowsEpisodesAsPlayIsPressedUnlessAskedJustBefore() async throws {
        let stick = MockJellyfinServer.Item(name: "Stick", type: "Series")
        let mock = MockJellyfinServer(items: [stick, episode(1, of: stick)])
        let profile = try await signedIn(to: mock)
        let show = MediaItem(id: stick.id, name: "Stick", kind: .series)
        func asked() -> Int { mock.requests.count { $0.url?.path == "/Shows/\(stick.id)/Episodes" } }

        _ = await profile.nextEpisode(ofShow: show)
        _ = await profile.nextEpisode(ofShow: show)
        #expect(asked() == 2)

        // Prepared ahead, the answer is used once.
        profile.preparePlayback(of: show)
        await waitUntil { asked() == 3 }
        _ = await profile.nextEpisode(ofShow: show)
        #expect(asked() == 3)
        _ = await profile.nextEpisode(ofShow: show)
        #expect(asked() == 4)
    }

    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
