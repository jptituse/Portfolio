import Foundation
import PortfolioShared
import PortfolioSharedJellyfinClient
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedUI

/// Home, against a mock Jellyfin server.
@MainActor
struct HomeViewModelTests {
    let client = JellyfinServerClient.mocked
    let movies = MockJellyfinServer.Library(name: "Movies", collectionType: "movies")
    let shows = MockJellyfinServer.Library(name: "Shows", collectionType: "tvshows")

    func signIn(to mock: MockJellyfinServer) async throws -> UserSession {
        let server = try await client.validateServer(at: mock.url)
        return try await client.signIn(to: server, username: "alex", password: "hunter2")
    }

    /// Requests for the banner: the latest items across every library.
    func bannerRequests(to mock: MockJellyfinServer) -> Int {
        mock.requests.count { $0.url?.path == "/Items/Latest" && !($0.url?.query()?.contains("parentId") ?? false) }
    }

    func movie(_ name: String, watched: Int = 0) -> MockJellyfinServer.Item {
        var item = MockJellyfinServer.Item(name: name, libraryID: movies.id)
        item.runtimeMinutes = 120
        item.watchedMinutes = watched
        return item
    }

    func episode(_ name: String, of show: String, season: Int, number: Int, watched: Int = 0, isNextUp: Bool = false) -> MockJellyfinServer.Item {
        var item = MockJellyfinServer.Item(name: name, type: "Episode", libraryID: shows.id)
        item.seriesName = show
        item.seriesID = "show-\(show)"
        item.seasonNumber = season
        item.episodeNumber = number
        item.runtimeMinutes = 50
        item.watchedMinutes = watched
        item.isNextUp = isNextUp
        return item
    }

    // MARK: The banner

    @Test func goesThroughTheEightNewestItemsInTheBanner() async throws {
        let mock = MockJellyfinServer(libraries: [movies], items: (1...10).map { movie("Movie \($0)") })
        let home = HomeViewModel(client: client, session: try await signIn(to: mock))

        await home.load()

        #expect(home.bannerItems.map(\.name) == (1...8).map { "Movie \($0)" })
        #expect(home.message == nil)
        #expect(!home.isLoading)
    }

    // MARK: Continue Watching

    @Test func continuesWithWhatsPartlyWatchedThenTheNextEpisodes() async throws {
        let mock = MockJellyfinServer(libraries: [movies, shows], items: [
            movie("Arrival", watched: 30),
            episode("The Bridge", of: "Andor", season: 1, number: 5, isNextUp: true),
            movie("Dune"),
        ])
        let home = HomeViewModel(client: client, session: try await signIn(to: mock))

        await home.load()

        let continueWatching = try #require(home.groups.first)
        #expect(continueWatching.title == "Continue Watching")
        #expect(continueWatching.style == .inProgress)
        #expect(continueWatching.items.map(\.name) == ["Arrival", "The Bridge"])
    }

    @Test func listsAShowOnceWhenAnEpisodeOfItIsPartlyWatched() async throws {
        let resumed = [MediaItem(id: "e4", name: "Four", kind: .episode, episode: EpisodeInfo(seriesID: "andor"))]
        let nextUp = [
            MediaItem(id: "e5", name: "Five", kind: .episode, episode: EpisodeInfo(seriesID: "andor")),
            MediaItem(id: "s2", name: "Pilot", kind: .episode, episode: EpisodeInfo(seriesID: "severance")),
            MediaItem(id: "e4", name: "Four", kind: .episode, episode: EpisodeInfo(seriesID: "andor")),
        ]

        let group = HomeViewModel.continueWatching(resume: resumed, nextUp: nextUp)

        #expect(group?.items.map(\.id) == ["e4", "s2"])
    }

    @Test func hasNoContinueWatchingRowWithNothingToContinue() {
        #expect(HomeViewModel.continueWatching(resume: [], nextUp: []) == nil)
    }

    // MARK: Latest

    @Test func showsTheLatestOfEachLibraryInTheUsersOrder() async throws {
        let mock = MockJellyfinServer(libraries: [shows, movies], items: [
            movie("Dune"),
            MockJellyfinServer.Item(name: "Severance", type: "Series", libraryID: shows.id),
            movie("Arrival"),
        ])
        let home = HomeViewModel(client: client, session: try await signIn(to: mock))

        await home.load()

        #expect(home.groups.map(\.title) == ["Latest Shows", "Latest Movies"])
        #expect(home.groups.last?.items.map(\.name) == ["Dune", "Arrival"])
        #expect(home.groups.allSatisfy { $0.style == .posters })
    }

    @Test func leavesOutTheLibrariesTheUserLeftOutOfTheirLatest() async throws {
        let mock = MockJellyfinServer(
            libraries: [movies, shows],
            items: [movie("Dune"), MockJellyfinServer.Item(name: "Severance", type: "Series", libraryID: shows.id)],
            librariesLeftOutOfLatest: [shows.id]
        )
        let home = HomeViewModel(client: client, session: try await signIn(to: mock))

        await home.load()

        #expect(home.groups.map(\.title) == ["Latest Movies"])
    }

    @Test func leavesOutLibrariesWithNothingInThem() async throws {
        let mock = MockJellyfinServer(libraries: [movies, shows], items: [movie("Dune")])
        let home = HomeViewModel(client: client, session: try await signIn(to: mock))

        await home.load()

        #expect(home.groups.map(\.title) == ["Latest Movies"])
    }

    @Test(arguments: [Library.Kind.collections, .playlists, .liveTV])
    func hasNoLatestRowForLibrariesWhoseItemsArentAddedAsSuch(_ kind: Library.Kind) {
        #expect(!HomeViewModel.hasLatestItems(kind))
    }

    @Test func putsContinueWatchingFirst() async throws {
        let mock = MockJellyfinServer(libraries: [movies], items: [movie("Arrival", watched: 30), movie("Dune")])
        let home = HomeViewModel(client: client, session: try await signIn(to: mock))

        await home.load()

        #expect(home.groups.map(\.title) == ["Continue Watching", "Latest Movies"])
    }

    // MARK: Loading again

    @Test func drawsArtworkFromTheProfilesServer() async throws {
        let mock = MockJellyfinServer()
        let session = try await signIn(to: mock)

        let home = HomeViewModel(client: client, session: session)

        #expect((home.images as? JellyfinImageResolver)?.server == session.server)
    }

    @Test func loadsAgainEachTimeItShowsAndPicksUpWhatsNew() async throws {
        let mock = MockJellyfinServer(libraries: [movies], items: [movie("Arrival")])
        let home = HomeViewModel(client: client, session: try await signIn(to: mock))
        await home.load()

        mock.items.insert(movie("Dune"), at: 0)
        await home.load()

        #expect(bannerRequests(to: mock) == 2)
        #expect(home.bannerItems.map(\.name) == ["Dune", "Arrival"])
        #expect(home.groups.first?.items.map(\.name) == ["Dune", "Arrival"])
    }

    @Test func keepsItsRowsWhenNothingChanged() async throws {
        let mock = MockJellyfinServer(libraries: [movies], items: [movie("Arrival")])
        let home = HomeViewModel(client: client, session: try await signIn(to: mock))
        await home.load()
        let rows = home.groups

        await home.load()

        #expect(home.groups == rows)
        #expect(home.message == nil)
    }

    @Test func keepsShowingItsRowsWhileLoadingAgain() async throws {
        let mock = MockJellyfinServer(libraries: [movies], items: [movie("Arrival")])
        let home = HomeViewModel(client: client, session: try await signIn(to: mock))
        await home.load()

        let again = Task { await home.load() }
        await Task.yield()

        #expect(!home.isLoading)
        #expect(!home.groups.isEmpty)
        await again.value
    }

    @Test func keepsItsRowsWhenItCannotBringThemUpToDate() async throws {
        let mock = MockJellyfinServer(name: "Living Room", libraries: [movies], items: [movie("Arrival")])
        let home = HomeViewModel(client: client, session: try await signIn(to: mock))
        await home.load()
        mock.revokeAllSessions()

        await home.load()

        #expect(home.bannerItems.map(\.name) == ["Arrival"])
        #expect(home.groups.first?.items.map(\.name) == ["Arrival"])
        #expect(home.message == "Living Room no longer accepts this sign-in. Switch profiles to sign in again.")
    }

    @Test func keepsLoadingWhenTheViewThatAskedGoesAway() async throws {
        let mock = MockJellyfinServer(libraries: [movies], items: [movie("Arrival")])
        let home = HomeViewModel(client: client, session: try await signIn(to: mock))

        // SwiftUI cancels a view's task when it replaces the view, and the new one asks again.
        let replacedView = Task { await home.load() }
        await Task.yield()
        replacedView.cancel()
        await home.load()

        #expect(home.bannerItems.map(\.name) == ["Arrival"])
        #expect(home.message == nil)
        #expect(bannerRequests(to: mock) == 1)
    }

    // MARK: Messages

    @Test func saysWhenNothingHasBeenAddedYet() async throws {
        let mock = MockJellyfinServer(items: [])
        let home = HomeViewModel(client: client, session: try await signIn(to: mock))

        await home.load()

        #expect(home.bannerItems.isEmpty)
        #expect(home.groups.isEmpty)
        #expect(home.message == "Nothing has been added to your libraries yet.")
        #expect(!home.canRetry)
    }

    @Test func explainsAServerItCannotReach() async {
        let home = HomeViewModel(client: client, session: .sample(server: ServerInfo(
            id: "gone",
            name: "Living Room",
            version: "10.11.2",
            url: MockJellyfinServer.uniqueURL()
        )))

        await home.load()

        #expect(home.groups.isEmpty)
        #expect(home.message == "Couldn't reach Living Room. Check that it's still running, and try again.")
        #expect(home.canRetry)
    }

    @Test func explainsASignInTheServerNoLongerAccepts() async throws {
        let mock = MockJellyfinServer(name: "Living Room")
        let home = HomeViewModel(client: client, session: try await signIn(to: mock))
        mock.revokeAllSessions()

        await home.load()

        #expect(home.message == "Living Room no longer accepts this sign-in. Switch profiles to sign in again.")
    }

    @Test func triesAgainAfterAFailure() async {
        let mock = MockJellyfinServer(name: "Living Room", behavior: .failing(status: 500))
        let home = HomeViewModel(client: client, session: .sample(server: ServerInfo(id: "s", name: "Living Room", version: "10.11.2", url: mock.url)))
        await home.load()
        #expect(home.message == "Living Room ran into a problem loading what's new. Try again in a moment.")
        // Home's requests go out together, and the first to fail cancels the rest, so how many reach
        // the server varies; trying again sends more.
        let requests = mock.requests.count

        await home.load()

        #expect(mock.requests.count > requests)
    }

    @Test func hasNothingToLoadWithoutAProfile() async {
        let home = HomeViewModel(client: client, session: nil)

        await home.load()

        #expect(home.groups.isEmpty)
        #expect(home.images == nil)
    }
}
