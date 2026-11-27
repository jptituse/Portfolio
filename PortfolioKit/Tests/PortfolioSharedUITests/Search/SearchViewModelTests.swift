import CoreGraphics
import Foundation
import PortfolioShared
import PortfolioSharedJellyfinClient
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedUI

/// Search, against a mock Jellyfin server.
@MainActor
struct SearchViewModelTests {
    let client = JellyfinServerClient.mocked

    /// Kept for the whole test: a mock server that's gone answers nothing.
    let mock = Self.makeMock()

    static func makeMock() -> MockJellyfinServer {
        var arrival = MockJellyfinServer.Item(name: "Arrival", genres: ["Drama"])
        arrival.people = [.init(name: "Amy Adams", imageTag: "i-amy")]
        var pilot = MockJellyfinServer.Item(name: "Dune Pilot", type: "Episode")
        pilot.seriesName = "Dune: Prophecy"
        pilot.seasonNumber = 1
        pilot.episodeNumber = 1
        return MockJellyfinServer(items: [
            arrival,
            MockJellyfinServer.Item(name: "Dune", genres: ["Drama"]),
            MockJellyfinServer.Item(name: "Dune: Prophecy", type: "Series", genres: ["Drama"]),
            MockJellyfinServer.Item(name: "Dune Collection", type: "BoxSet"),
            MockJellyfinServer.Item(name: "Dune (Live)", type: "MusicVideo", genres: ["Music"]),
            pilot,
        ])
    }

    func search(on mock: MockJellyfinServer, typingPause: Duration = .milliseconds(50)) async throws -> SearchViewModel {
        let session = try await client.signIn(to: try await client.validateServer(at: mock.url), username: "alex", password: "hunter2")
        return SearchViewModel(client: client, session: session, typingPause: typingPause, settleDelay: .milliseconds(50))
    }

    /// How many searches the server got: Top Results and People each ask for people.
    func searches(to mock: MockJellyfinServer) -> Int {
        mock.requests.count { $0.url?.path == "/Persons" || ($0.url?.path == "/Items" && $0.url?.query()?.contains("Movie") == true) }
    }

    /// The item types each `/Items` request asked for.
    func itemTypesAsked(of mock: MockJellyfinServer) -> [Set<String>] {
        mock.requests.filter { $0.url?.path == "/Items" }.map { request in
            let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
            return Set(query.filter { $0.name == "includeItemTypes" }.compactMap(\.value))
        }
    }

    /// Waits for `condition`, for far longer than these tests' short delays.
    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func searched(_ text: String, on mock: MockJellyfinServer) async throws -> SearchViewModel {
        let search = try await search(on: mock)
        search.text = text
        await waitUntil { search.resultsTerm == text }
        return search
    }

    // MARK: Top Results

    @Test func findsTitlesTogetherWithEpisodesAndPeopleBelow() async throws {
        let search = try await searched("dune", on: mock)

        #expect(Set(search.items.map(\.name)) == ["Dune", "Dune: Prophecy", "Dune Collection", "Dune (Live)"])
        #expect(search.episodes.map(\.name) == ["Dune Pilot"])
        #expect(search.people.isEmpty)
        #expect(search.gridShape == .poster, "Music videos among other titles keep the grid even")
        #expect(search.message == nil)
    }

    @Test func findsPeople() async throws {
        let search = try await searched("amy", on: mock)

        #expect(search.items.isEmpty)
        #expect(search.people.map(\.name) == ["Amy Adams"])
        #expect(search.pictureURL(of: search.people[0], pixelSize: CGSize(width: 200, height: 200))?.path().hasSuffix("/Images/Primary") == true)
    }

    @Test func suggestsTheNamesFound() async throws {
        let search = try await searched("dune", on: mock)

        #expect(Set(search.suggestions) == ["Dune", "Dune: Prophecy", "Dune Collection", "Dune (Live)"])
    }

    @Test func showsTheFiltersWithAnythingInThemOnceSomethingsTyped() async throws {
        let search = try await search(on: mock)
        search.loadGenres()
        await waitUntil { !search.genres.isEmpty }
        #expect(!search.showsFilters)

        search.text = "dune"
        #expect(search.showsFilters)
        #expect(search.filters == [.topResults], "Until Top Results is answered, only it is known to show")
        await waitUntil { search.resultsTerm == "dune" }

        // No one's called Dune.
        #expect(search.filters == [.topResults, .movies, .shows, .musicVideos, .collections, .episodes, drama, music])
    }

    @Test func hidesTheFiltersWithNothingInThem() async throws {
        let search = try await search(on: mock)
        search.loadGenres()
        await waitUntil { !search.genres.isEmpty }

        search.text = "arrival"
        await waitUntil { search.resultsTerm == "arrival" }

        #expect(search.filters == [.topResults, .movies, drama])
    }

    @Test func keepsTheChosenFilterWhenItFindsNothing() async throws {
        let search = try await searched("dune", on: mock)
        search.filterSelected(.musicVideos)
        await waitUntil { search.resultsFilter == .musicVideos }

        search.text = "dune:"
        await waitUntil { search.resultsTerm == "dune:" }

        #expect(search.items.isEmpty)
        #expect(search.filters == [.topResults, .shows, .musicVideos], "The filter showing shouldn't disappear")
    }

    @Test func searchingAFilterFindsWhichFiltersHaveAnything() async throws {
        let search = try await searched("dune", on: mock)
        search.filterSelected(.shows)
        await waitUntil { search.resultsFilter == .shows }

        search.text = "arrival"
        await waitUntil { search.resultsTerm == "arrival" }

        #expect(search.resultsFilter == .shows)
        #expect(search.filters == [.topResults, .movies, .shows])
        // Top Results, kept for the text, shows at once.
        let asked = mock.requests.count
        search.filterSelected(.topResults)
        #expect(search.items.map(\.name) == ["Arrival"])
        #expect(mock.requests.count == asked)
    }

    var drama: SearchFilter { .genre(Genre(id: MockJellyfinServer.genreID("Drama"), name: "Drama")) }
    var music: SearchFilter { .genre(Genre(id: MockJellyfinServer.genreID("Music"), name: "Music")) }

    // MARK: Filters

    @Test func aFilterShowsItsKindOnly() async throws {
        let search = try await searched("dune", on: mock)

        search.filterSelected(.musicVideos)
        await waitUntil { search.resultsFilter == .musicVideos }

        #expect(search.items.map(\.name) == ["Dune (Live)"])
        #expect(search.episodes.isEmpty)
        #expect(search.gridShape == .still)
    }

    @Test func peoplesFilterShowsOnlyPeople() async throws {
        let search = try await searched("a", on: mock)

        search.filterSelected(.people)
        await waitUntil { search.resultsFilter == .people }

        #expect(search.items.isEmpty)
        #expect(search.people.map(\.name) == ["Amy Adams"])
    }

    @Test func aGenreFindsWhatsInIt() async throws {
        let search = try await searched("dune", on: mock)

        search.filterSelected(.genre(Genre(id: MockJellyfinServer.genreID("Drama"), name: "Drama")))
        await waitUntil { search.resultsFilter != .topResults }

        #expect(Set(search.items.map(\.name)) == ["Dune", "Dune: Prophecy"])
    }

    @Test func aFilterIsChosenOnceFocusRestsOnIt() async throws {
        let search = try await searched("dune", on: mock)

        search.filterFocused(.movies)
        search.filterFocused(.shows)
        #expect(search.chosenFilter == .topResults, "Passing over filters shouldn't choose them")
        await waitUntil { search.resultsFilter == .shows }

        #expect(search.chosenFilter == .shows)
        #expect(search.items.map(\.name) == ["Dune: Prophecy"])
        #expect(!itemTypesAsked(of: mock).contains(["Movie"]), "Movies, passed over, shouldn't be searched")
    }

    @Test func goingBackToAFilterShowsWhatItFoundAtOnce() async throws {
        let search = try await searched("dune", on: mock)
        search.filterSelected(.movies)
        await waitUntil { search.resultsFilter == .movies }
        let asked = mock.requests.count

        search.filterSelected(.topResults)

        #expect(search.resultsFilter == .topResults)
        #expect(search.episodes.map(\.name) == ["Dune Pilot"])
        #expect(mock.requests.count == asked, "What Top Results found should be kept for the same text")
    }

    @Test func typingSearchesTheChosenFilter() async throws {
        let search = try await searched("dune", on: mock)
        search.filterSelected(.shows)
        await waitUntil { search.resultsFilter == .shows }

        search.text = "dune:"
        await waitUntil { search.resultsTerm == "dune:" }

        #expect(search.resultsFilter == .shows)
        #expect(search.items.map(\.name) == ["Dune: Prophecy"])
    }

    // MARK: Typing

    @Test func waitsForTypingToPauseBeforeSearching() async throws {
        let search = try await search(on: mock, typingPause: .milliseconds(200))

        for text in ["d", "du", "dun", "dune"] {
            search.text = text
            try await Task.sleep(for: .milliseconds(20))
        }
        await waitUntil { search.resultsTerm != nil }

        #expect(search.resultsTerm == "dune")
        #expect(searches(to: mock) == 2, "Only the text typing paused on should be searched: its titles and people")
    }

    @Test func keepsWhatsShowingUntilTheNextAnswer() async throws {
        let search = try await search(on: mock, typingPause: .milliseconds(200))
        search.text = "dune"
        await waitUntil { search.resultsTerm == "dune" }

        search.text = "arrival"

        #expect(search.items.contains { $0.name == "Dune" }, "The results shouldn't blank while typing")
        await waitUntil { search.resultsTerm == "arrival" }
        #expect(search.items.map(\.name) == ["Arrival"])
    }

    @Test func clearingTheTextClearsTheResultsAtOnce() async throws {
        let search = try await searched("dune", on: mock)

        search.text = ""

        #expect(search.items.isEmpty)
        #expect(search.resultsTerm == nil)
        #expect(search.message == nil)
        #expect(!search.showsFilters)
    }

    @Test func spacesAroundTheTextDontSearchAgain() async throws {
        let search = try await searched("dune", on: mock)

        search.text = "dune "
        try await Task.sleep(for: .milliseconds(200))

        #expect(searches(to: mock) == 2)
        #expect(search.resultsTerm == "dune")
    }

    @Test func typingBackToWhatsShowingCancelsTheSearchOnItsWay() async throws {
        let search = try await search(on: mock, typingPause: .milliseconds(100))
        search.text = "dune"
        await waitUntil { search.resultsTerm == "dune" }

        search.text = "dune c"
        search.text = "dune"
        try await Task.sleep(for: .milliseconds(300))

        #expect(searches(to: mock) == 2)
        #expect(search.items.count == 4)
    }

    @Test func saysWhenNothingMatches() async throws {
        let search = try await searched("zzz", on: mock)

        #expect(search.items.isEmpty)
        #expect(search.message == "Nothing matches “zzz”.")
    }

    @Test func saysWhenTheServerCantBeSearched() async throws {
        let search = try await search(on: mock)
        mock.revokeAllSessions()

        search.text = "dune"
        await waitUntil { search.resultsTerm == "dune" }

        #expect(search.items.isEmpty)
        #expect(search.message == "Living Room no longer accepts this sign-in. Switch profiles to sign in again.")
    }

    // MARK: Cards

    @Test func fetchesPostersStillsAndFullScreenArtAtTheirSizes() async throws {
        let search = try await search(on: mock)
        search.setArtworkSizes(
            poster: CGSize(width: 260, height: 390),
            still: CGSize(width: 420, height: 236),
            screen: CGSize(width: 1920, height: 1080),
            logo: CGSize(width: 400, height: 150),
            scale: 2
        )
        search.text = "dune"
        await waitUntil { search.resultsTerm == "dune" }

        let movie = search.card(for: try #require(search.items.first { $0.name == "Dune" }))
        let musicVideo = search.card(for: try #require(search.items.first { $0.name == "Dune (Live)" }))
        let episode = search.card(for: search.episodes[0])
        #expect(movie.posterArtworkSize == CGSize(width: 600, height: 800))
        #expect(musicVideo.posterArtworkSize == CGSize(width: 600, height: 800), "Among other titles, a music video is a poster")
        #expect(episode.posterArtworkSize == CGSize(width: 900, height: 500))
        #expect(movie.landscapeArtworkSize == CGSize(width: 3900, height: 2200))

        search.filterSelected(.musicVideos)
        await waitUntil { search.resultsFilter == .musicVideos }
        #expect(search.card(for: search.items[0]).posterArtworkSize == CGSize(width: 900, height: 500), "On their own, music videos are stills")
    }

    @Test func captionsEpisodesWithTheirShowAndNumber() async throws {
        let search = try await searched("dune", on: mock)

        #expect(search.caption(of: search.episodes[0]) == "Dune: Prophecy · S1, E1")
        #expect(search.caption(of: try #require(search.items.first)) == nil)
    }

    @Test func warmsOnlyTheFocusedPostersArt() async throws {
        let search = try await searched("dune", on: mock)
        let first = search.items[0]
        let second = search.items[1]

        search.posterFocused(first)
        search.posterFocused(second)

        #expect(!search.card(for: first).isWarm)
        #expect(search.card(for: second).isWarm)
    }
}
