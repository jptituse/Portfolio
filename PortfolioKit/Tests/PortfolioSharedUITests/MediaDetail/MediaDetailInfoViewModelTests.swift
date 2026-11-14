import PortfolioShared
import Testing

@testable import PortfolioSharedUI

@MainActor
struct MediaDetailInfoViewModelTests {
    @Test func formatsTheTitleMetadataAndOverview() {
        let viewModel = MediaDetailInfoViewModel(
            item: MediaItem(
                id: "1",
                name: "A Movie",
                kind: .movie,
                overview: "What happens in it.",
                productionYear: 2024,
                runtime: .seconds(6960),
                officialRating: "PG-13",
                genres: ["Drama", "Science Fiction"]
            )
        )

        #expect(viewModel.title == "A Movie")
        #expect(viewModel.metadata == "2024 · 1h 56m · PG-13 · Drama, Science Fiction")
        #expect(viewModel.overview == "What happens in it.")
    }

    @Test func titlesAnEpisodeByItsShowAndPutsItsNumberAndNameFirst() {
        let viewModel = MediaDetailInfoViewModel(
            item: MediaItem(
                id: "1",
                name: "The Bridge",
                kind: .episode,
                productionYear: 2022,
                runtime: .seconds(3120),
                episode: EpisodeInfo(seriesName: "Andor", seasonNumber: 1, episodeNumber: 5)
            )
        )

        #expect(viewModel.title == "Andor")
        #expect(viewModel.metadata == "S1E5 · The Bridge · 2022 · 52m")
    }

    @Test func leavesOutWhatTheItemDoesNotHave() {
        let viewModel = MediaDetailInfoViewModel(
            item: MediaItem(id: "1", name: "A Movie", kind: .movie, productionYear: 2024, genres: ["Drama"])
        )

        #expect(viewModel.metadata == "2024 · Drama")
        #expect(viewModel.overview == nil)
    }

    @Test func hasNoMetadataLineWhenTheItemHasNothingToShow() {
        let viewModel = MediaDetailInfoViewModel(item: MediaItem(id: "1", name: "A Movie", kind: .movie))
        #expect(viewModel.metadata == nil)
    }
}
