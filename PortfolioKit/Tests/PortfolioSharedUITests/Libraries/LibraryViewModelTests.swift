import CoreGraphics
import Foundation
import PortfolioShared
import PortfolioSharedJellyfinClient
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedUI

/// A library view, against a mock Jellyfin server.
@MainActor
struct LibraryViewModelTests {
    let client = JellyfinServerClient.mocked
    let movies = MockJellyfinServer.Library(name: "Movies", collectionType: "movies")

    /// Twelve movies, most recently added first: "Movie 12" down to "Movie 01".
    func mock(count: Int = 12) -> MockJellyfinServer {
        MockJellyfinServer(libraries: [movies], items: (1..<count + 1).reversed().map { number in
            .init(name: String(format: "Movie %02d", number), libraryID: movies.id, genres: number.isMultiple(of: 3) ? ["Drama"] : ["Comedy"])
        })
    }

    let pipeline = ImagePipeline(configuration: MockJellyfinServer.sessionConfiguration)

    func library(on mock: MockJellyfinServer, pageSize: Int = 5, refreshAfter: Duration = .seconds(10)) async throws -> LibraryViewModel {
        let session = try await client.signIn(to: try await client.validateServer(at: mock.url), username: "alex", password: "hunter2")
        return LibraryViewModel(
            scope: .kind(.movies),
            client: client,
            session: session,
            pipeline: pipeline,
            settleDelay: .milliseconds(50),
            firstPageSize: pageSize,
            pageSize: pageSize,
            refreshAfter: refreshAfter
        )
    }

    func requests(to mock: MockJellyfinServer, for sidebarItem: String) -> Int {
        mock.requests.count { $0.url?.path == "/Items" && ($0.url?.query()?.contains(sidebarItem) ?? false) }
    }

    func itemRequests(to mock: MockJellyfinServer) -> Int {
        mock.requests.count { $0.url?.path == "/Items" }
    }

    /// Waits for `condition`, for far longer than these tests' short delays.
    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    var drama: LibrarySidebarItem {
        .genre(Genre(id: MockJellyfinServer.genreID("Drama"), name: "Drama"))
    }

    // MARK: Sidebar items

    @Test func namesItsSidebarItems() async throws {
        let mock = mock()
        let library = try await library(on: mock)

        #expect(library.title == "Movies")
        #expect(library.mainSidebarItems.map(library.title(of:)) == ["Recently Added", "All Movies"])
        #expect(library.title(of: drama) == "Drama")
    }

    @Test func startsOnRecentlyAddedWithTheGenresBelow() async throws {
        let mock = mock()
        let library = try await library(on: mock)
        #expect(library.isLoading)

        await library.load()

        #expect(library.shownSidebarItem == .recentlyAdded)
        #expect(library.items.map(\.name) == ["Movie 12", "Movie 11", "Movie 10", "Movie 09", "Movie 08"])
        #expect(library.genres.map(\.name) == ["Comedy", "Drama"])
        #expect(!library.isLoading)
    }

    // MARK: Following focus

    @Test func showsASidebarItemOnceFocusRestsOnIt() async throws {
        let mock = mock()
        let library = try await library(on: mock)
        await library.load()

        library.sidebarItemFocused(.all)
        #expect(library.shownSidebarItem == .recentlyAdded)
        await waitUntil { library.shownSidebarItem == .all }

        #expect(library.items.first?.name == "Movie 01")
    }

    @Test func passesOverSidebarItemsFocusDoesNotRestOn() async throws {
        let mock = mock()
        let library = try await library(on: mock)
        await library.load()

        library.sidebarItemFocused(.all)
        library.sidebarItemFocused(drama)
        await waitUntil { library.shownSidebarItem == drama }

        #expect(library.chosenSidebarItem == drama)
        #expect(library.items.map(\.name) == ["Movie 03", "Movie 06", "Movie 09", "Movie 12"])
    }

    @Test func keepsTheChosenSidebarItemWhenFocusMovesIntoTheGrid() async throws {
        let mock = mock()
        let library = try await library(on: mock)
        await library.load()
        library.sidebarItemFocused(.all)
        await waitUntil { library.shownSidebarItem == .all }

        library.sidebarItemFocused(nil)
        try await Task.sleep(for: .milliseconds(150))

        #expect(library.shownSidebarItem == .all)
    }

    @Test func showsASidebarItemItHasShownBeforeAtOnceAndChecksItAgainAfterAWhile() async throws {
        let mock = mock()
        let library = try await library(on: mock, refreshAfter: .milliseconds(200))
        await library.load()
        library.sidebarItemFocused(.all)
        await waitUntil { library.shownSidebarItem == .all }
        try await Task.sleep(for: .milliseconds(250))
        let requests = requests(to: mock, for: "DateCreated")

        library.sidebarItemFocused(.recentlyAdded)
        await waitUntil { library.shownSidebarItem == .recentlyAdded }

        #expect(library.items.first?.name == "Movie 12")
        await waitUntil { self.requests(to: mock, for: "DateCreated") > requests }
        #expect(self.requests(to: mock, for: "DateCreated") == requests + 1)
    }

    @Test func doesNotCheckASidebarItemAgainThatHasJustLoaded() async throws {
        let mock = mock()
        let library = try await library(on: mock)
        await library.load()

        // Focus reaching All loads it; it's then chosen, and not loaded again.
        library.sidebarItemFocused(.all)
        await waitUntil { library.shownSidebarItem == .all }
        try await Task.sleep(for: .milliseconds(100))

        let allRequests = mock.requests.count { request in
            let query = request.url?.query() ?? ""
            return request.url?.path == "/Items" && !query.contains("DateCreated") && !query.contains("genreIds")
        }
        #expect(allRequests == 1)
    }

    @Test func loadsEverySidebarItemsFirstPageAheadOnceTheGenresAreKnown() async throws {
        let mock = mock()
        let library = try await library(on: mock)

        await library.load()

        for genre in ["Comedy", "Drama"] {
            #expect(requests(to: mock, for: "genreIds=\(MockJellyfinServer.genreID(genre))") == 1)
        }
        #expect(library.shownSidebarItem == .recentlyAdded)
    }

    @Test func loadsThePostersOfTheSidebarItemsBesideTheFocusedOneAhead() async throws {
        // Sidebar items: Recently Added, All, Action, Comedy, Drama, Western. "Item 20" comes after the
        // first posters of Recently Added and All, so only Action, its one genre, would load its
        // poster.
        let genres = [20: "Action", 1: "Comedy", 2: "Drama", 3: "Western"]
        let mock = MockJellyfinServer(libraries: [movies], items: (1...20).map { number in
            .init(name: String(format: "Item %02d", number), imageTags: ["Primary": "p\\(number)"], libraryID: movies.id, genres: genres[number].map { [$0] } ?? [])
        })
        let library = try await library(on: mock, pageSize: 30)
        library.setArtworkSizes(poster: CGSize(width: 250, height: 375), screen: CGSize(width: 1920, height: 1080), logo: CGSize(width: 520, height: 160), scale: 2)
        await library.load()
        let item20 = try #require(library.items.first { $0.name == "Item 20" })
        let poster = try #require(library.card(for: item20).posterArtworkURL)

        // Drama is beside Comedy and Western, not Action.
        library.sidebarItemFocused(library.genres.first { $0.name == "Drama" }.map(LibrarySidebarItem.genre))
        try await Task.sleep(for: .milliseconds(200))
        #expect(pipeline.cachedImage(for: poster) == nil)

        library.sidebarItemFocused(library.genres.first { $0.name == "Comedy" }.map(LibrarySidebarItem.genre))
        await waitUntil { pipeline.cachedImage(for: poster) != nil }
        #expect(pipeline.cachedImage(for: poster) != nil)
    }

    @Test func loadsASidebarItemsFirstPostersAhead() async throws {
        let mock = MockJellyfinServer(libraries: [movies], items: [.init(name: "Arrival", imageTags: ["Primary": "p1"], libraryID: movies.id)])
        let library = try await library(on: mock)
        library.setArtworkSizes(poster: CGSize(width: 250, height: 375), screen: CGSize(width: 1920, height: 1080), logo: CGSize(width: 520, height: 160), scale: 2)

        await library.load()

        let poster = try #require(library.card(for: library.items[0]).posterArtworkURL)
        await waitUntil { pipeline.cachedImage(for: poster) != nil }
        #expect(pipeline.cachedImage(for: poster) != nil)
    }

    @Test func readiesOnlyTheFocusedPostersLandscapeArtForItToGrowInto() async throws {
        let mock = mock()
        let library = try await library(on: mock)
        await library.load()
        let first = library.card(for: library.items[0])
        let second = library.card(for: library.items[1])

        library.posterFocused(library.items[0])
        #expect(first.isWarm)
        #expect(!second.isWarm)

        library.posterFocused(library.items[1])
        #expect(!first.isWarm)
        #expect(second.isWarm)
    }

    // MARK: Pages

    @Test func loadsTheNextPageAsTheGridNearsTheEnd() async throws {
        let mock = mock()
        let library = try await library(on: mock)
        await library.load()
        #expect(library.items.count == 5)

        library.itemAppeared(library.items[4])
        await waitUntil { library.items.count == 10 }
        library.itemAppeared(library.items[9])
        await waitUntil { library.items.count == 12 }
        let requests = itemRequests(to: mock)

        // There's no more to load.
        library.itemAppeared(library.items[11])
        try await Task.sleep(for: .milliseconds(100))

        #expect(library.items.map(\.name).last == "Movie 01")
        #expect(itemRequests(to: mock) == requests)
    }

    @Test func loadsEachPageOnceWhileItsOnItsWay() async throws {
        let mock = mock()
        let library = try await library(on: mock)
        await library.load()
        let requests = itemRequests(to: mock)

        library.itemAppeared(library.items[3])
        library.itemAppeared(library.items[4])
        await waitUntil { library.items.count == 10 }

        #expect(itemRequests(to: mock) == requests + 1)
    }

    @Test func waitsToLoadMoreUntilTheGridNearsTheEnd() async throws {
        let mock = mock(count: 40)
        let library = try await library(on: mock, pageSize: 30)
        await library.load()
        let requests = itemRequests(to: mock)

        library.itemAppeared(library.items[0])
        try await Task.sleep(for: .milliseconds(100))

        #expect(itemRequests(to: mock) == requests)
    }

    // MARK: Loading again

    @Test func picksUpWhatsNewWhenShownAgain() async throws {
        let mock = mock()
        let library = try await library(on: mock)
        await library.load()

        mock.items.insert(.init(name: "Movie 13", libraryID: movies.id), at: 0)
        await library.load()

        #expect(library.items.first?.name == "Movie 13")
    }

    @Test func keepsWhatsLoadedWhenNothingChanged() async throws {
        let mock = mock()
        let library = try await library(on: mock)
        await library.load()
        library.itemAppeared(library.items[4])
        await waitUntil { library.items.count == 10 }

        await library.load()

        #expect(library.items.count == 10)
    }

    // MARK: Messages

    @Test func explainsAServerItCannotReach() async {
        let library = LibraryViewModel(
            scope: .kind(.movies),
            client: client,
            session: .sample(server: ServerInfo(id: "gone", name: "Living Room", version: "10.11.2", url: MockJellyfinServer.uniqueURL()))
        )

        await library.load()

        #expect(library.message == "Couldn't reach Living Room. Check that it's still running, and try again.")
        #expect(!library.isLoading)
    }

    @Test func saysWhenASidebarItemIsEmpty() async throws {
        let mock = mock(count: 0)
        let library = try await library(on: mock)
        await library.load()
        #expect(library.message == "Nothing here yet.")
    }

    // MARK: Cards

    @Test func fetchesArtworkAtTheSizesTheGridAndTheDetailDrawIt() async throws {
        let mock = mock()
        let library = try await library(on: mock)
        await library.load()

        library.setArtworkSizes(poster: CGSize(width: 250, height: 375), screen: CGSize(width: 1920, height: 1080), logo: CGSize(width: 520, height: 160), scale: 2)
        let card = library.card(for: library.items[0])

        #expect(card.posterArtworkSize == CGSize(width: 500, height: 800))
        #expect(card.landscapeArtworkSize == CGSize(width: 3900, height: 2200))
        #expect(card === library.card(for: library.items[0]))
    }

    @Test func drawsPostersInTheShapeOfItsKind() {
        #expect(LibraryViewModel(scope: .kind(.movies), client: client, session: nil).posterAspectRatio == 2.0 / 3)
        #expect(LibraryViewModel(scope: .kind(.musicVideos), client: client, session: nil).posterAspectRatio == 16.0 / 9)
    }
}
