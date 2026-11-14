import Foundation
import JellyfinAPI
import PortfolioShared
import Testing

@testable import PortfolioSharedJellyfinClient

struct MediaModelMappingTests {
    @Test func mapsAMovie() throws {
        let item = try #require(MediaItem(Fixture.decode(BaseItemDto.self, from: "movie")))

        #expect(item.id == "3e5c7a9b1d2f4e6a8c0b2d4f6a8c0e2b")
        #expect(item.name == "Arrival")
        #expect(item.kind == .movie)
        #expect(item.overview?.hasPrefix("A linguist") == true)
        #expect(item.productionYear == 2016)
        #expect(item.runtime == .seconds(6978))
        #expect(item.officialRating == "PG-13")
        #expect(abs((item.communityRating ?? 0) - 7.9) < 0.001)
        #expect(item.genres == ["Drama", "Science Fiction"])
        #expect(item.images == [.primary: "p-4f1c", .logo: "l-9a2e", .thumb: "t-77b0", .backdrop(): "b-0d13", .backdrop(index: 1): "b-58aa"])
        #expect(item.primaryImageAspectRatio == 2.0 / 3)
        #expect(item.userData == UserData(isPlayed: false, isFavorite: true, playbackPosition: .seconds(3600), playCount: 1))
    }

    @Test func mapsAnEpisodeWithItsPlaceInItsShow() throws {
        let item = try #require(MediaItem(Fixture.decode(BaseItemDto.self, from: "episode")))

        #expect(item.kind == .episode)
        #expect(item.episode?.seriesName == "Andor")
        #expect(item.episode?.seriesID == "5d4c3b2a1f0e9d8c7b6a5f4e3d2c1b0a")
        #expect(item.episode?.seasonNumber == 1)
        #expect(item.episode?.episodeNumber == 5)
        #expect(item.runtime == .seconds(3120))
    }

    @Test func keepsAnEpisodesOwnArtworkAndTheShowsItShows() throws {
        let item = try #require(MediaItem(Fixture.decode(BaseItemDto.self, from: "episode")))

        // Its own still.
        #expect(item.images == [.primary: "ep-1c2d"])
        #expect(item.episode?.seriesImages == [
            .thumb: "st-6a7b",
            .logo: "sl-4e5f",
            .backdrop(): "sb-0a1b",
            .backdrop(index: 1): "sb-2c3d",
        ])
    }

    @Test func leavesOutArtworkAnEpisodeShowsFromItsSeason() throws {
        var dto = try Fixture.decode(BaseItemDto.self, from: "episode")
        dto.parentBackdropItemID = "season"

        let item = try #require(MediaItem(dto))

        #expect(item.episode?.seriesImages[.backdrop()] == nil)
        #expect(item.episode?.seriesImages[.logo] == "sl-4e5f")
    }

    @Test func hasNoEpisodeDetailsForAMovie() throws {
        #expect(try MediaItem(Fixture.decode(BaseItemDto.self, from: "movie"))?.episode == nil)
    }

    @Test func fillsDefaultsForSparseItems() throws {
        var dto = BaseItemDto()
        dto.id = "abc"
        let item = try #require(MediaItem(dto))

        #expect(item.name == "")
        #expect(item.kind == .other("Unknown"))
        #expect(item.runtime == nil)
        #expect(item.genres.isEmpty)
        #expect(item.images == [:])
        #expect(item.userData == UserData())
    }

    @Test func dropsItemsWithoutAnID() {
        #expect(MediaItem(BaseItemDto(name: "No ID")) == nil)
    }

    @Test func mapsLibrariesByCollectionType() throws {
        let views = try Fixture.decode(BaseItemDtoQueryResult.self, from: "user-views")
        let libraries = (views.items ?? []).compactMap(Library.init)

        #expect(libraries.map(\.name) == ["Movies", "Shows", "Everything Else", "Books"])
        #expect(libraries.map(\.kind) == [.movies, .tvShows, .mixed, .other("books")])
        #expect(libraries[0].images[.primary] == "v-movies")
        #expect(libraries[1].images[.primary] == nil)
    }

    @Test func convertsTicksToDurations() {
        #expect(Duration(ticks: 10_000_000) == .seconds(1))
        #expect(Duration(ticks: 0) == .zero)
    }
}
