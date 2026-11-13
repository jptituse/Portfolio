import PortfolioShared
import PortfolioSharedJellyfinClient
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedUI

@MainActor
struct LibrariesViewModelTests {
    func library(_ name: String, _ kind: Library.Kind) -> Library {
        Library(id: name, name: name, kind: kind)
    }

    @Test func givesEachStandardKindOneEntryInAFixedOrder() {
        let arranged = LibrariesViewModel.arrange([
            library("Shows", .tvShows),
            library("Playlists", .playlists),
            library("Movies", .movies),
            library("Collections", .collections),
            library("Music Videos", .musicVideos),
        ])

        #expect(arranged.standard == [.kind(.movies), .kind(.tvShows), .kind(.collections), .kind(.playlists), .kind(.musicVideos)])
        #expect(arranged.special.isEmpty)
    }

    @Test func listsOnlyTheKindsTheProfileHas() {
        let arranged = LibrariesViewModel.arrange([library("Movies", .movies)])
        #expect(arranged.standard == [.kind(.movies)])
    }

    @Test func listsOtherLibrariesOnTheirOwnInTheServersOrder() {
        let music = library("Music", .music)
        let home = library("Home Videos", .homeVideos)
        let mixed = library("Everything", .mixed)

        let arranged = LibrariesViewModel.arrange([music, library("Movies", .movies), home, mixed])

        #expect(arranged.special == [.library(music), .library(home), .library(mixed)])
    }

    @Test func alsoListsEachLibraryOfAStandardKindThatHasSeveral() {
        let movies = library("Movies", .movies)
        let movies4K = library("4K Movies", .movies)
        let shows = library("Shows", .tvShows)
        let music = library("Music", .music)

        let arranged = LibrariesViewModel.arrange([movies, shows, music, movies4K])

        #expect(arranged.standard == [.kind(.movies), .kind(.tvShows)])
        // The only TV library needs no entry of its own.
        #expect(arranged.special == [.library(movies), .library(music), .library(movies4K)])
    }

    @Test func loadsTheProfilesLibraries() async throws {
        let mock = MockJellyfinServer(libraries: [
            .init(name: "Movies", collectionType: "movies"),
            .init(name: "Music", collectionType: "music"),
        ])
        let client = JellyfinServerClient.mocked
        let session = try await client.signIn(to: try await client.validateServer(at: mock.url), username: "alex", password: "hunter2")
        let libraries = LibrariesViewModel(client: client, session: session)

        await libraries.load()

        #expect(libraries.standard == [.kind(.movies)])
        #expect(libraries.special.map(\.title) == ["Music"])
    }

    @Test func keepsTheLibrariesWhenTheyCannotBeLoadedAgain() async throws {
        let mock = MockJellyfinServer(libraries: [.init(name: "Movies", collectionType: "movies")])
        let client = JellyfinServerClient.mocked
        let session = try await client.signIn(to: try await client.validateServer(at: mock.url), username: "alex", password: "hunter2")
        let libraries = LibrariesViewModel(client: client, session: session)
        await libraries.load()
        mock.revokeAllSessions()

        await libraries.load()

        #expect(libraries.standard == [.kind(.movies)])
    }

    @Test func keepsEachLibraryViewAsItWasLeft() {
        let libraries = LibrariesViewModel.preview()
        #expect(libraries.viewModel(for: .kind(.movies)) === libraries.viewModel(for: .kind(.movies)))
        #expect(libraries.viewModel(for: .kind(.movies)) !== libraries.viewModel(for: .kind(.tvShows)))
    }

    // MARK: Names

    @Test func namesKindsAndLibraries() {
        #expect(LibraryScope.kind(.movies).title == "Movies")
        #expect(LibraryScope.kind(.tvShows).title == "TV Shows")
        #expect(LibraryScope.kind(.musicVideos).title == "Music Videos")
        #expect(LibraryScope.library(library("4K Movies", .movies)).title == "4K Movies")
    }

    @Test func givesEachKindAnIcon() {
        #expect(LibraryScope.kind(.movies).systemImage == "film")
        #expect(LibraryScope.library(library("Music", .music)).systemImage == "music.note")
        #expect(LibraryScope.library(library("Stuff", .mixed)).systemImage == "folder")
    }
}
