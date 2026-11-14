import Testing

@testable import PortfolioShared

struct MediaItemImagesTests {
    let show = EpisodeInfo(seriesID: "show", seriesImages: [.thumb: "st", .logo: "sl", .backdrop(): "sb0", .backdrop(index: 1): "sb1"])

    func episode(_ images: [MediaImageKind: String]) -> MediaItem {
        MediaItem(id: "episode", name: "The Bridge", kind: .episode, images: images, episode: show)
    }

    @Test func showsAnItemsOwnImage() {
        let movie = MediaItem(id: "movie", name: "Arrival", kind: .movie, images: [.primary: "p"])

        #expect(movie.image(.primary)?.ownerID == "movie")
        #expect(movie.image(.primary)?.tag == "p")
        #expect(!movie.hasImage(.backdrop()))
    }

    @Test func showsItsShowsImagesWhereAnEpisodeHasNone() {
        let episode = episode([.primary: "still"])

        #expect(episode.image(.primary)?.ownerID == "episode")
        #expect(episode.image(.logo)?.ownerID == "show")
        #expect(episode.image(.logo)?.tag == "sl")
        #expect(episode.image(.backdrop(index: 1))?.tag == "sb1")
    }

    @Test func showsAnEpisodesOwnImagesOverItsShows() {
        let episode = episode([.logo: "own-logo"])

        #expect(episode.image(.logo)?.ownerID == "episode")
        #expect(episode.image(.logo)?.tag == "own-logo")
        #expect(episode.image(.thumb)?.ownerID == "show")
    }

    @Test func showsOnlyAnEpisodesOwnBackdropsWhenItHasAny() {
        let episode = episode([.backdrop(): "own"])

        #expect(episode.image(.backdrop())?.tag == "own")
        #expect(!episode.hasImage(.backdrop(index: 1)))
    }
}
