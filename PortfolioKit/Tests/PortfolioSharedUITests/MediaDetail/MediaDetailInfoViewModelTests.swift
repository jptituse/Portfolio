import Foundation
import PortfolioShared
import Testing

@testable import PortfolioSharedUI

@MainActor
struct MediaDetailInfoViewModelTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func formatsWhatTheItemIsWhatHappensAndWhenItsFrom() {
        let viewModel = MediaDetailInfoViewModel(
            item: MediaItem(
                id: "1",
                name: "A Movie",
                kind: .movie,
                overview: "What happens in it.",
                productionYear: 2024,
                runtime: .seconds(6960),
                officialRating: "PG-13",
                communityRating: 7.94,
                genres: ["Drama", "Science Fiction"],
                criticRating: 94
            ),
            now: now
        )

        #expect(viewModel.title == "A Movie")
        #expect(viewModel.event == nil)
        #expect(viewModel.criticScore == 94)
        #expect(viewModel.communityRating == 7.9.formatted(.number.precision(.fractionLength(1))))
        #expect(viewModel.classification == "Movie · Drama · Science Fiction")
        #expect(viewModel.contentRating == "PG-13")
        #expect(viewModel.episodeLead == nil)
        #expect(viewModel.overview == "What happens in it.")
        #expect(viewModel.info(timeLeft: nil) == "2024 · 1h 56m")
        // Time left to watch in place of the length.
        #expect(viewModel.info(timeLeft: "1h 12m left") == "2024 · 1h 12m left")
    }

    @Test func titlesAnEpisodeByItsShowAndLeadsItsOverviewWithItsNumberAndName() {
        let viewModel = MediaDetailInfoViewModel(
            item: MediaItem(
                id: "1",
                name: "The Bridge",
                kind: .episode,
                overview: "Cassian flees.",
                productionYear: 2022,
                runtime: .seconds(3120),
                episode: EpisodeInfo(seriesName: "Andor", seasonNumber: 1, episodeNumber: 5)
            ),
            now: now
        )

        #expect(viewModel.title == "Andor")
        // What its own page titles it by, under its show.
        #expect(viewModel.episodeTitle == "The Bridge")
        #expect(viewModel.classification == "TV Show")
        #expect(viewModel.episodeLead == "S1, E5 · The Bridge")
        #expect(viewModel.episodeNumber == "S1, E5")
        #expect(viewModel.info(timeLeft: nil) == "2022 · 52m")
        #expect(MediaDetailInfoViewModel(item: MediaItem(id: "2", name: "Arrival", kind: .movie)).episodeTitle == nil)
    }

    @Test func saysAnItemWasRecentlyAddedForTwoWeeks() {
        func event(addedDaysAgo days: Double) -> String? {
            MediaDetailInfoViewModel(
                item: MediaItem(id: "1", name: "A Movie", kind: .movie, dateAdded: now.addingTimeInterval(-days * 24 * 60 * 60)),
                now: now
            ).event
        }

        #expect(event(addedDaysAgo: 3) == "Recently Added")
        #expect(event(addedDaysAgo: 13.9) == "Recently Added")
        #expect(event(addedDaysAgo: 15) == nil)
    }

    @Test func saysAShowHasANewSeasonOverThatItWasRecentlyAdded() {
        let show = MediaItem(id: "stick", name: "Stick", kind: .series, dateAdded: now.addingTimeInterval(-3600), hasNewSeason: true)

        #expect(MediaDetailInfoViewModel(item: show, now: now).event == "New Season")
    }

    @Test func describesAShowsNextEpisodeInPlaceOfTheShow() {
        let viewModel = MediaDetailInfoViewModel(item: MediaItem(id: "stick", name: "Stick", kind: .series, overview: "A golfer coaches a prodigy."), now: now)
        let episode = MediaItem(
            id: "e3",
            name: "Dead Reckoning",
            kind: .episode,
            overview: "Supplies run low.",
            episode: EpisodeInfo(seriesName: "Stick", seriesID: "stick", seasonNumber: 1, episodeNumber: 3)
        )

        viewModel.update(nextEpisode: episode, isWatched: false)

        #expect(viewModel.title == "Stick")
        #expect(viewModel.episodeLead == "S1, E3 · Dead Reckoning")
        #expect(viewModel.overview(hidingSpoilers: false) == "Supplies run low.")
        // Not watched yet, it's a spoiler.
        #expect(viewModel.overview(hidingSpoilers: true) == nil)
    }

    @Test func leavesOutWhatTheItemDoesNotHave() {
        let viewModel = MediaDetailInfoViewModel(item: MediaItem(id: "1", name: "A Folder", kind: .folder))

        #expect(viewModel.classification == "")
        #expect(viewModel.contentRating == nil)
        #expect(viewModel.criticScore == nil)
        #expect(viewModel.overview == nil)
        #expect(viewModel.info(timeLeft: nil) == nil)
    }

    @Test func takesTheCriticsScoreFromTheDetailsWhereTheItemHasNone() {
        let viewModel = MediaDetailInfoViewModel(item: MediaItem(id: "1", name: "A Movie", kind: .movie))

        viewModel.update(with: MediaItemDetails(criticRating: 71.6))

        #expect(viewModel.criticScore == 72)
    }

    @Test func creditsTheFirstThreeActorsAndTheDirectors() {
        let actors = ["Amy Adams", "Jeremy Renner", "Forest Whitaker", "Michael Stuhlbarg"].map { Credit(personID: $0, name: $0, kind: .actor) }

        #expect(MediaDetailInfoViewModel.creditLines(actors + [Credit(personID: "d", name: "Denis Villeneuve", kind: .director)]) == [
            .init(label: "Starring", names: "Amy Adams, Jeremy Renner, Forest Whitaker"),
            .init(label: "Director", names: "Denis Villeneuve"),
        ])
        #expect(MediaDetailInfoViewModel.creditLines([
            Credit(personID: "a", name: "Joel Coen", kind: .director),
            Credit(personID: "b", name: "Ethan Coen", kind: .director),
        ]) == [.init(label: "Directors", names: "Joel Coen, Ethan Coen")])
        #expect(MediaDetailInfoViewModel.creditLines([]).isEmpty)
    }

    @Test func showsTheBadgesAndCreditsOnceTheDetailsAreIn() {
        let viewModel = MediaDetailInfoViewModel(item: MediaItem(id: "1", name: "A Movie", kind: .movie))
        #expect(viewModel.badges.isEmpty)
        #expect(viewModel.credits.isEmpty)

        viewModel.update(with: MediaItemDetails(
            credits: [Credit(personID: "a", name: "Amy Adams", kind: .actor)],
            version: MediaVersion(video: MediaVersion.Video(width: 3840, height: 2160, dynamicRange: .hdr10))
        ))

        #expect(viewModel.badges == ["4K", "HDR10"])
        #expect(viewModel.credits == [.init(label: "Starring", names: "Amy Adams")])
    }
}
