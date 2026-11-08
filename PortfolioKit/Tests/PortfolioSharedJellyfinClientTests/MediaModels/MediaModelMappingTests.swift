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
        #expect(item.images == ImageTags(primary: "p-4f1c", logo: "l-9a2e", thumb: "t-77b0", backdrops: ["b-0d13", "b-58aa"]))
        #expect(item.userData == UserData(isPlayed: false, isFavorite: true, playbackPosition: .seconds(3600), playCount: 1))
    }

    @Test func fillsDefaultsForSparseItems() throws {
        var dto = BaseItemDto()
        dto.id = "abc"
        let item = try #require(MediaItem(dto))

        #expect(item.name == "")
        #expect(item.kind == .other("Unknown"))
        #expect(item.runtime == nil)
        #expect(item.genres.isEmpty)
        #expect(item.images == ImageTags())
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
        #expect(libraries[0].images.primary == "v-movies")
        #expect(libraries[1].images.primary == nil)
    }

    @Test func convertsTicksToDurations() {
        #expect(Duration(ticks: 10_000_000) == .seconds(1))
        #expect(Duration(ticks: 0) == .zero)
    }
}
