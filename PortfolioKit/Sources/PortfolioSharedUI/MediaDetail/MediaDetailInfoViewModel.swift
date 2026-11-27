import Foundation
import Observation
import PortfolioShared

/// What `MediaDetailInfoView` shows for an item, already formatted, in the TV app's order: an event
/// ("Recently Added"), the logo or title, what it is (critics' score, kind, genres and rating), what
/// happens in it, then when it's from, how long it is and its file's format.
@MainActor
@Observable
final class MediaDetailInfoViewModel {
    private(set) var title = ""
    /// An episode's own name, which its own page titles it by, under its show's.
    private(set) var episodeTitle: String?
    /// Where the item's logo is, shown in place of the title, or nil to show the title.
    var logoURL: URL?
    /// Over the logo: "New Season" for a show listed for a season just added to it, "Recently Added"
    /// for an item added in the last two weeks, else nil.
    private(set) var event: String?
    /// Critics' score out of 100, beside a tomato, before what the item is.
    private(set) var criticScore: Int?
    /// The community's rating out of 10, beside a star: "7.9".
    private(set) var communityRating: String?
    /// What the item is: "Movie · Drama · Science Fiction", "TV Show · Comedy".
    private(set) var classification = ""
    /// Its content rating, boxed after its classification: "PG-13".
    private(set) var contentRating: String?
    /// What leads an episode's overview: "S1, E5 · The Bridge". A show's shows its next episode's.
    private(set) var episodeLead: String?
    /// An episode's place in its show alone, which leads its overview on its own page, titled by its
    /// name already: "S1, E5".
    private(set) var episodeNumber: String?
    private(set) var overview: String?
    /// When it's from: its year, which the info line starts with.
    private(set) var year: String?
    /// How long it is, unless the card has time left to give instead.
    private(set) var runtime: String?
    /// Whether it's an episode the profile hasn't watched, whose overview gives away what happens in it.
    private(set) var isUnwatchedEpisode = false
    /// The file's format, small, at the end of the info line, as the TV app badges it: "4K", "Dolby
    /// Vision", "Dolby Atmos", "SDH". None until the item's details are in.
    private(set) var badges: [String] = []
    /// Who's in it and who made it, beside a full-screen card's details: "Starring" its first three
    /// actors, and its director. None until the item's details are in.
    private(set) var credits: [CreditLine] = []

    /// A credit beside a full-screen card's details: "Starring", then names.
    struct CreditLine: Hashable {
        let label: String
        let names: String
    }

    init(item: MediaItem, now: Date = .now) {
        update(with: item, now: now)
    }

    /// An episode's title is its show's, whose logo it shows; its own number and name lead its overview.
    func update(with item: MediaItem, now: Date = .now) {
        title = item.episode?.seriesName ?? item.name
        episodeTitle = item.episode == nil || item.name.isEmpty ? nil : item.name
        event = item.hasNewSeason
            ? String(localized: "New Season")
            : item.dateAdded.flatMap { now.timeIntervalSince($0) < Self.recentlyAdded ? String(localized: "Recently Added") : nil }
        criticScore = item.criticRating.map { Int($0.rounded()) }
        communityRating = item.communityRating.map { $0.formatted(.number.precision(.fractionLength(1))) }
        classification = ([Self.kindName(item.kind)] + item.genres).compactMap { $0 }.joined(separator: " · ")
        contentRating = item.officialRating
        episodeLead = Self.lead(of: item)
        episodeNumber = item.episode?.longLabel
        overview = item.overview
        year = item.productionYear.map(String.init)
        runtime = item.runtime.map { $0.formatted(.units(allowed: [.hours, .minutes], width: .narrow)) }
        isUnwatchedEpisode = item.episode != nil && !item.userData.isPlayed
    }

    /// A show's next episode, which Play plays: its number and name lead its overview, in place of the
    /// show's, as the TV app's.
    ///
    /// - Parameter isWatched: whether the profile has watched it, so its overview isn't a spoiler.
    func update(nextEpisode episode: MediaItem, isWatched: Bool) {
        episodeLead = Self.lead(of: episode)
        overview = episode.overview
        isUnwatchedEpisode = !isWatched
    }

    /// "S1, E5 · The Bridge", for an episode.
    private static func lead(of item: MediaItem) -> String? {
        item.episode.map { episode in
            [episode.longLabel, item.name.isEmpty ? nil : item.name].compactMap { $0 }.joined(separator: " · ")
        }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The badges and credits from the item's details, once they're in.
    func update(with details: MediaItemDetails) {
        badges = details.version?.badges ?? []
        credits = Self.creditLines(details.credits)
        if criticScore == nil { criticScore = details.criticRating.map { Int($0.rounded()) } }
    }

    /// The info line before the badges: "2016 · 1h 56m", or with time left to watch, "2016 · 1h 12m left".
    func info(timeLeft: String?) -> String? {
        let parts = [year, timeLeft ?? runtime].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The overview to show, none for an episode not watched yet while `hidingSpoilers`.
    func overview(hidingSpoilers: Bool) -> String? {
        hidingSpoilers && isUnwatchedEpisode ? nil : overview
    }

    /// "Starring" the first three actors, then "Director" or "Directors".
    static func creditLines(_ credits: [Credit]) -> [CreditLine] {
        let actors = credits.filter { $0.kind == .actor }.prefix(Self.starringCount).map(\.name)
        let directors = credits.filter { $0.kind == .director }.map(\.name)
        var lines: [CreditLine] = []
        if !actors.isEmpty { lines.append(CreditLine(label: "Starring", names: actors.joined(separator: ", "))) }
        if !directors.isEmpty { lines.append(CreditLine(label: directors.count == 1 ? "Director" : "Directors", names: directors.joined(separator: ", "))) }
        return lines
    }

    /// How many actors "Starring" names, as the TV app's.
    static let starringCount = 3
    /// How long an item counts as recently added: two weeks.
    static let recentlyAdded: TimeInterval = 14 * 24 * 60 * 60

    private static func kindName(_ kind: MediaItem.Kind) -> String? {
        switch kind {
        case .movie: String(localized: "Movie")
        case .series, .season, .episode: String(localized: "TV Show")
        case .boxSet: String(localized: "Collection")
        case .musicVideo: String(localized: "Music Video")
        case .folder, .other: nil
        }
    }
}
