import CoreGraphics
import Foundation
import PortfolioShared
import Testing

@testable import PortfolioSharedUI

@MainActor
struct MediaDetailViewModelTests {
    let arrival = MediaItem(
        id: "arrival",
        name: "Arrival",
        kind: .movie,
        overview: "A linguist is recruited.",
        productionYear: 2016,
        runtime: .seconds(6960),
        officialRating: "PG-13",
        communityRating: 7.9,
        genres: ["Drama", "Science Fiction"]
    )

    let details = MediaItemDetails(
        credits: [
            Credit(personID: "amy", name: "Amy Adams", kind: .actor, role: "Louise Banks", imageTag: "i-amy"),
            Credit(personID: "jeremy", name: "Jeremy Renner", kind: .actor, role: "Ian Donnelly"),
            Credit(personID: "denis", name: "Denis Villeneuve", kind: .director),
            Credit(personID: "eric", name: "Eric Heisserer", kind: .writer, role: "Screenplay"),
            // Credited twice: shown once.
            Credit(personID: "denis", name: "Denis Villeneuve", kind: .producer),
        ],
        studios: ["FilmNation Entertainment", "Lava Bear Films"],
        releaseDate: Date(timeIntervalSince1970: 1_478_736_000),
        countries: ["United States of America"],
        tagline: "Why are they here?",
        criticRating: 94,
        version: MediaVersion(
            container: "mkv",
            size: 58_237_419_520,
            bitrate: 66_512_000,
            video: MediaVersion.Video(
                codec: "hevc",
                profile: "Main 10",
                width: 3840,
                height: 2160,
                frameRate: 23.976,
                bitDepth: 10,
                bitrate: 58_000_000,
                dynamicRange: .dolbyVision(profile: 8, level: 6, compatibility: 1, hasEnhancementLayer: false, fallback: .hdr10)
            ),
            audio: [
                MediaVersion.Audio(title: "English", language: "eng", codec: "truehd", channels: 8, channelLayout: "7.1", spatialAudio: .dolbyAtmos, isDefault: true, bitrate: 4_500_000),
                MediaVersion.Audio(title: "French", language: "fre", codec: "ac3", channels: 6, channelLayout: "5.1"),
            ],
            subtitles: [
                MediaVersion.Subtitles(title: "English SDH", language: "eng", isForHearingImpaired: true, isText: false),
                MediaVersion.Subtitles(title: "French Forced", language: "fre", isForced: true),
            ]
        )
    )

    func page(details: MediaItemDetails? = nil, similar: [MediaItem]? = nil, failing: Bool = false, asks: Asks = Asks()) -> MediaDetailViewModel {
        MediaDetailViewModel(
            card: MediaCardViewModel(item: arrival),
            loadDetails: { [self] in
                asks.details += 1
                if failing { throw URLError(.notConnectedToInternet) }
                return self.details
            },
            loadSimilar: {
                asks.similar += 1
                return [MediaItem(id: "dune", name: "Dune", kind: .movie)]
            },
            images: DescribingPictures(),
            details: details,
            similar: similar
        )
    }

    @Test func loadsTheItemsDetailsAndItemsLikeIt() async {
        let asks = Asks()
        let page = page(asks: asks)

        await page.load()
        await page.load()

        #expect(page.details == details)
        #expect(page.similar.map(\.item.name) == ["Dune"])
        #expect(asks.details == 1)
        #expect(asks.similar == 1)
        // The card shows its badges and credits.
        #expect(page.card.detailInfo.badges == ["4K", "Dolby Vision", "Dolby Atmos", "SDH"])
        #expect(page.card.detailInfo.credits.map(\.label) == ["Starring", "Director"])
    }

    @Test func opensOnWhatsKnownWithoutAskingAgain() async {
        let asks = Asks()
        let page = page(details: details, similar: [MediaItem(id: "dune", name: "Dune", kind: .movie)], asks: asks)

        #expect(page.people.count == 4)
        #expect(page.card.detailInfo.badges.contains("4K"))
        await page.load()
        #expect(asks.details == 0)
        #expect(asks.similar == 0)
    }

    @Test func saysWhenItCouldntLoadTheDetails() async {
        let page = page(failing: true)

        await page.load()

        #expect(page.details == nil)
        #expect(page.failure == "Couldn't load more about Arrival.")
        // What the item has already still shows.
        #expect(page.columns.map(\.title) == ["Information"])
    }

    @Test func listsEachPersonOnceWithTheirCharacterOrPart() {
        let page = page(details: details)

        #expect(page.people.map(\.name) == ["Amy Adams", "Jeremy Renner", "Denis Villeneuve", "Eric Heisserer"])
        #expect(page.people.map(\.role) == ["Louise Banks", "Ian Donnelly", "Director", "Screenplay"])
        let size = CGSize(width: 520, height: 520)
        #expect(page.pictureURL(of: page.people[0], pixelSize: size)?.absoluteString == "https://images.test/people/amy/520")
        #expect(page.pictureURL(of: page.people[1], pixelSize: size) == nil)
    }

    @Test func scoresTheCommunityAndCritics() {
        #expect(page(details: details).ratings == [
            MediaDetailViewModel.Rating(value: "7.9", label: "Community Rating"),
            MediaDetailViewModel.Rating(value: "94%", label: "Critics"),
        ])
    }

    @Test func endsWithInformationLanguagesAccessibilityAndTheFile() throws {
        let columns = page(details: details).columns

        #expect(columns.map(\.title) == ["Information", "Languages", "Accessibility", "File"])
        #expect(columns[0].facts.map(\.label) == ["Studios", "Released", "Run Time", "Rated", "Genres", "Region of Origin"])
        // A day, the server's midnight in UTC, wherever the TV is.
        #expect(columns[0].facts[1].value == Date(timeIntervalSince1970: 1_478_736_000).formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: .gmt)))
        #expect(columns[1].facts.map(\.label) == ["Audio", "Subtitles"])
        #expect(columns[1].facts[0].value.contains("(Dolby TrueHD Dolby Atmos 7.1)"))
        #expect(columns[1].facts[1].value.hasSuffix("(SDH), \(Locale.current.localizedString(forLanguageCode: "fre") ?? "fre") (Forced)"))
        #expect(columns[2].facts.map(\.label) == ["SDH"])
        #expect(columns[3].facts.map(\.label) == ["Video", "Dynamic Range", "Video Bitrate", "Audio", "File"])
        #expect(columns[3].facts[1].value == "Dolby Vision Profile 8.1, Level 6, HDR10 compatible")
        #expect(columns[3].facts[2].value == "58 Mbps")
        #expect(columns[3].facts[4].value == "MKV · \(Int64(58_237_419_520).formatted(.byteCount(style: .file))) · 66.5 Mbps")
    }

    @Test func fetchesSimilarItemsArtworkAtTheSizesTheyreDrawn() async {
        let page = page()
        page.setArtworkSizes(poster: CGSize(width: 260, height: 390), screen: CGSize(width: 1920, height: 1080), logo: CGSize(width: 520, height: 160), still: CGSize(width: 410, height: 230), scale: 2)

        await page.load()

        #expect(page.similar.first?.posterArtworkSize == CGSize(width: 600, height: 800))
        #expect(page.similar.first?.landscapeArtworkSize == CGSize(width: 3900, height: 2200))
    }

    // MARK: Seasons and episodes

    func episode(_ season: Int?, _ number: Int, seasonName: String? = nil, played: Bool = false, lastPlayed: TimeInterval? = nil) -> MediaItem {
        MediaItem(
            id: "s\(season ?? -1)e\(number)",
            name: "Episode \(number)",
            kind: .episode,
            userData: UserData(isPlayed: played, playbackPosition: lastPlayed != nil && !played ? .seconds(600) : .zero, lastPlayed: lastPlayed.map(Date.init(timeIntervalSince1970:))),
            episode: EpisodeInfo(seriesID: "stick", seasonNumber: season, episodeNumber: number, seasonName: seasonName)
        )
    }

    func showPage(_ episodes: [MediaItem], of item: MediaItem? = nil) -> MediaDetailViewModel {
        MediaDetailViewModel(
            card: MediaCardViewModel(item: item ?? MediaItem(id: "stick", name: "Stick", kind: .series)),
            loadDetails: { [self] in details },
            loadEpisodes: { episodes }
        )
    }

    @Test func listsTheShowsEpisodesSeasonBySeason() async {
        let page = showPage([episode(0, 1), episode(1, 1, seasonName: "Season One"), episode(1, 2), episode(2, 1)])

        await page.load()

        #expect(page.episodes.map(\.item.id) == ["s0e1", "s1e1", "s1e2", "s2e1"])
        #expect(page.seasons.map(\.name) == ["Specials", "Season One", "Season 2"])
        #expect(page.seasons.map(\.firstEpisodeID) == ["s0e1", "s1e1", "s2e1"])
    }

    @Test func aShowsPageDescribesTheEpisodePlayPlays() async {
        let page = showPage([episode(1, 1, played: true, lastPlayed: 100), episode(1, 2), episode(1, 3)])

        await page.load()

        #expect(page.card.detailInfo.episodeLead == "S1, E2 · Episode 2")
    }

    @Test func onlyAShowsOrAnEpisodesPageListsEpisodes() {
        #expect(MediaDetailViewModel.showID(of: MediaItem(id: "stick", name: "Stick", kind: .series)) == "stick")
        #expect(MediaDetailViewModel.showID(of: episode(1, 2)) == "stick")
        #expect(MediaDetailViewModel.showID(of: arrival) == nil)
    }

    @Test func startsWhereTheUserIsInTheShow() async {
        // Nothing played: the first episode outside the specials.
        var page = showPage([episode(0, 1), episode(1, 1), episode(1, 2)])
        await page.load()
        #expect(page.startingEpisodeID == "s1e1")

        // Partway through the episode played last.
        page = showPage([episode(1, 1, played: true, lastPlayed: 100), episode(1, 2, lastPlayed: 200), episode(1, 3)])
        await page.load()
        #expect(page.startingEpisodeID == "s1e2")

        // The one after the episode finished last, even into the next season.
        page = showPage([episode(1, 1, played: true, lastPlayed: 300), episode(1, 2, played: true, lastPlayed: 100), episode(2, 1)])
        await page.load()
        #expect(page.startingEpisodeID == "s1e2")
        page = showPage([episode(1, 1, played: true, lastPlayed: 100), episode(1, 2, played: true, lastPlayed: 200), episode(2, 1)])
        await page.load()
        #expect(page.startingEpisodeID == "s2e1")

        // An episode's page starts on that episode.
        page = showPage([episode(1, 1), episode(1, 2), episode(1, 3)], of: episode(1, 3))
        await page.load()
        #expect(page.startingEpisodeID == "s1e3")
    }

    @Test func fetchesEpisodesStillsAtTheSizeTheRowDrawsThem() async {
        let page = showPage([episode(1, 1)])
        page.setArtworkSizes(poster: CGSize(width: 260, height: 390), screen: CGSize(width: 1920, height: 1080), logo: CGSize(width: 520, height: 160), still: CGSize(width: 410, height: 230), scale: 2)

        await page.load()

        #expect(page.episodes.first?.posterArtworkSize == CGSize(width: 900, height: 500))
        #expect(page.episodes.first?.landscapeArtworkSize == CGSize(width: 900, height: 500))
    }

    @Test func givesAnEpisodesPageTheSameCardEachTimeAtFullScreensSize() async throws {
        let page = showPage([episode(1, 1), episode(1, 2)])
        page.setArtworkSizes(poster: CGSize(width: 260, height: 390), screen: CGSize(width: 1920, height: 1080), logo: CGSize(width: 520, height: 160), still: CGSize(width: 410, height: 230), scale: 2)
        await page.load()
        let still = try #require(page.episodes.last)

        let card = page.pageCard(for: still)

        // The page built ahead for it is the one that opens.
        #expect(page.pageCard(for: still) === card)
        #expect(page.pageCard(forEpisode: "s1e2") === card)
        #expect(page.pageCard(forEpisode: "s9e9") == nil)
        #expect(card !== still)
        #expect(card.landscapeArtworkSize == CGSize(width: 3900, height: 2200))
    }
}

/// How many times a page asked for what it shows.
@MainActor
final class Asks {
    var details = 0
    var similar = 0
}

/// Answers with a URL naming whose picture was asked for, for anyone with one.
struct DescribingPictures: MediaImageResolver {
    func url(for item: MediaItem, _ kind: MediaImageKind, pixelSize: CGSize) -> URL? {
        nil
    }

    func url(for person: Person, pixelSize: CGSize) -> URL? {
        person.imageTag == nil ? nil : URL(string: "https://images.test/people/\(person.id)/\(Int(pixelSize.width))")
    }
}
