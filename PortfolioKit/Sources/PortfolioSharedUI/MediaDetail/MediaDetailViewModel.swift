import Foundation
import Observation
import PortfolioShared

/// An item's page, below its full-screen card, as the TV app's: a show's seasons and episodes, its cast
/// and crew, items like it, what it's about, and a block of facts at the end (information, languages,
/// accessibility and its file).
/// The page's top is the item's full-screen card, the very same card (`card`), so it shows what the card
/// shows.
@MainActor
@Observable
public final class MediaDetailViewModel: Identifiable {
    /// The card the page grew out of, whose details and actions are the page's top.
    public let card: MediaCardViewModel
    public let id = UUID()

    /// What the server said about the item beyond its card, once it has.
    public private(set) var details: MediaItemDetails?
    /// Cards of items like it, most alike first, once the server has said which.
    public private(set) var similar: [MediaCardViewModel] = []
    /// Cards of every episode of its show, season by season, on a show's page or an episode's, once the
    /// server has said which.
    public private(set) var episodes: [MediaCardViewModel] = []
    /// Why its details couldn't be loaded, if they couldn't.
    public private(set) var failure: String?

    @ObservationIgnored private let loadDetails: @MainActor () async throws -> MediaItemDetails
    @ObservationIgnored private let loadSimilar: @MainActor () async throws -> [MediaItem]
    @ObservationIgnored private let loadEpisodes: (@MainActor () async throws -> [MediaItem])?
    @ObservationIgnored private let images: (any MediaImageResolver)?
    @ObservationIgnored private let userDataUpdates: UserDataUpdates?
    @ObservationIgnored private var loading: Task<Void, Never>?

    /// - Parameters:
    ///   - card: the card it grows out of.
    ///   - loadDetails: finds what the item's page shows beyond its card, such as by asking its server.
    ///   - loadSimilar: finds items like it.
    ///   - loadEpisodes: finds its show's episodes, for a show or an episode.
    ///   - images: where people's pictures and similar items' artwork are.
    ///   - userDataUpdates: where the user got to in what they've played here, for similar items' cards.
    ///   - details: the item's details, if they're known already, so it opens on them.
    ///   - similar: items like it, if they're known already.
    ///   - episodes: its show's episodes, if they're known already.
    public init(
        card: MediaCardViewModel,
        loadDetails: @escaping @MainActor () async throws -> MediaItemDetails,
        loadSimilar: @escaping @MainActor () async throws -> [MediaItem] = { [] },
        loadEpisodes: (@MainActor () async throws -> [MediaItem])? = nil,
        images: (any MediaImageResolver)? = nil,
        userDataUpdates: UserDataUpdates? = nil,
        details: MediaItemDetails? = nil,
        similar: [MediaItem]? = nil,
        episodes: [MediaItem]? = nil
    ) {
        self.card = card
        self.loadDetails = loadDetails
        self.loadSimilar = loadSimilar
        self.loadEpisodes = loadEpisodes
        self.images = images
        self.userDataUpdates = userDataUpdates
        self.details = details
        if let details { card.detailInfo.update(with: details) }
        self.similar = (similar ?? []).map { MediaCardViewModel(item: $0, images: images, userDataUpdates: userDataUpdates) }
        self.episodes = (episodes ?? []).map { MediaCardViewModel(item: $0, images: images, userDataUpdates: userDataUpdates) }
        showNextEpisode()
        // All known: nothing to load.
        if details != nil, similar != nil, loadEpisodes == nil || episodes != nil { loading = Task {} }
    }

    /// The show whose episodes `item`'s page lists: its own, for a show, or an episode's.
    public static func showID(of item: MediaItem) -> String? {
        switch item.kind {
        case .series: item.id
        case .episode: item.episode?.seriesID
        default: nil
        }
    }

    public var item: MediaItem { card.item }

    /// The sizes similar items' artwork is fetched at: posters as the row draws them, landscape art and
    /// logos as their full-screen cards do. Episodes' stills are fetched as their row draws them.
    @ObservationIgnored private var artworkSizes: (poster: CGSize, screen: CGSize, logo: CGSize, still: CGSize)?

    /// Sets the sizes, in points, similar items' artwork and episodes' stills are drawn at on a `scale`
    /// screen.
    public func setArtworkSizes(poster: CGSize, screen: CGSize, logo: CGSize, still: CGSize, scale: CGFloat) {
        artworkSizes = (
            RemoteImageViewModel.requestSize(for: poster, scale: scale),
            RemoteImageViewModel.requestSize(for: screen, scale: scale),
            RemoteImageViewModel.requestSize(for: logo, scale: scale),
            RemoteImageViewModel.requestSize(for: still, scale: scale)
        )
        similar.forEach(setArtworkSizes)
        episodes.forEach(setStillSize)
    }

    /// An episode's still, else its show's landscape art, at the size the row draws it.
    private func setStillSize(of card: MediaCardViewModel) {
        guard let artworkSizes else { return }
        card.posterArtworkSize = artworkSizes.still
        card.landscapeArtworkSize = artworkSizes.still
    }

    private func setArtworkSizes(of card: MediaCardViewModel) {
        guard let artworkSizes else { return }
        card.posterArtworkSize = artworkSizes.poster
        card.landscapeArtworkSize = artworkSizes.screen
        card.logoArtworkSize = artworkSizes.logo
    }

    /// Loads the item's details, items like it and its show's episodes, once; the card shows its badges
    /// and credits as soon as the details are in. It belongs to the page, not to the view's task, which
    /// SwiftUI can cancel.
    public func load() async {
        if loading == nil {
            loading = Task { [weak self, loadDetails, loadSimilar, loadEpisodes] in
                let similar = Task { (try? await loadSimilar()) ?? [] }
                let episodes = Task { (try? await loadEpisodes?()) ?? [] }
                let found: MediaItemDetails?
                do {
                    found = try await loadDetails()
                } catch {
                    found = nil
                }
                let alike = await similar.value
                let shown = await episodes.value
                guard let self else { return }
                if let found {
                    details = found
                    card.detailInfo.update(with: found)
                } else {
                    failure = "Couldn't load more about \(item.name)."
                }
                self.similar = alike.map { MediaCardViewModel(item: $0, images: images, userDataUpdates: userDataUpdates) }
                self.similar.forEach(setArtworkSizes)
                self.episodes = shown.map { MediaCardViewModel(item: $0, images: images, userDataUpdates: userDataUpdates) }
                self.episodes.forEach(setStillSize)
                showNextEpisode()
            }
        }
        await loading?.value
    }

    // MARK: Seasons and episodes

    /// A season of the show, as its tab above the episodes names it.
    public struct Season: Identifiable, Hashable {
        /// Its number, 0 for specials, or -1 for episodes in none.
        public let id: Int
        public let name: String
        /// Where it starts in the row of episodes.
        public let firstEpisodeID: MediaItem.ID
    }

    /// The show's seasons, in the order their episodes come.
    public var seasons: [Season] {
        var seasons: [Season] = []
        for card in episodes {
            let number = Self.seasonNumber(of: card.item)
            guard !seasons.contains(where: { $0.id == number }) else { continue }
            let name = card.item.episode?.seasonName ?? (number == 0 ? "Specials" : number < 0 ? "Episodes" : "Season \(number)")
            seasons.append(Season(id: number, name: name, firstEpisodeID: card.item.id))
        }
        return seasons
    }

    /// The season `item` is in, for its tab.
    public static func seasonNumber(of item: MediaItem) -> Int {
        item.episode?.seasonNumber ?? -1
    }

    /// The episode the row starts on: an episode's page's own; on a show's, where the user is in it
    /// (`startingEpisode(of:in:userData:)`), with what they've played here since.
    public var startingEpisodeID: MediaItem.ID? {
        let userData = Dictionary(episodes.map { ($0.item.id, $0.userData) }) { first, _ in first }
        return Self.startingEpisode(of: item, in: episodes.map(\.item)) { userData[$0.id] ?? $0.userData }?.id
    }

    /// On a show's page, its card describes the episode its row starts on, which Play plays.
    private func showNextEpisode() {
        guard item.kind == .series, let id = startingEpisodeID, let next = episodes.first(where: { $0.item.id == id }) else { return }
        card.detailInfo.update(nextEpisode: next.item, isWatched: next.userData.isPlayed)
    }

    /// The card of `episode`'s own page, opened from its row: its art fetched at the sizes a
    /// full-screen card's is, not the still's. The same each time, so the page built ahead for it is the
    /// one that opens.
    public func pageCard(for episode: MediaCardViewModel) -> MediaCardViewModel {
        if let card = pageCards[episode.item.id] { return card }
        let card = MediaCardViewModel(item: episode.item, images: images, userDataUpdates: userDataUpdates)
        setArtworkSizes(of: card)
        pageCards[episode.item.id] = card
        return card
    }

    /// The card of the page of the episode `id` in the show's row, if it's there.
    public func pageCard(forEpisode id: MediaItem.ID) -> MediaCardViewModel? {
        episodes.first { $0.item.id == id }.map(pageCard(for:))
    }

    @ObservationIgnored private var pageCards: [MediaItem.ID: MediaCardViewModel] = [:]

    /// Where the user is in a show, among its `episodes`, as the TV app has it, and so where its row of
    /// episodes starts and what Play on the show plays: the episode played last while it's partway
    /// through, else the one after it, else the first outside the specials. On an episode's page, that
    /// episode.
    ///
    /// - Parameter userData: where the user got to in an episode, newer than what it was loaded with if
    ///   it's been played here since.
    public static func startingEpisode(of item: MediaItem, in episodes: [MediaItem], userData: (MediaItem) -> UserData) -> MediaItem? {
        if item.kind == .episode, let own = episodes.first(where: { $0.id == item.id }) { return own }
        let played = episodes.indices.compactMap { index in userData(episodes[index]).lastPlayed.map { (index, $0) } }
        if let (last, _) = played.max(by: { $0.1 < $1.1 }) {
            if !userData(episodes[last]).isPlayed { return episodes[last] }
            if last + 1 < episodes.count { return episodes[last + 1] }
        }
        return episodes.first { seasonNumber(of: $0) != 0 } ?? episodes.first
    }

    // MARK: Cast and crew

    /// Someone in the cast and crew row: their picture, name, and character or job.
    public struct Person: Identifiable, Hashable {
        public let id: String
        public let name: String
        /// The character an actor plays, else a crew member's part: "Director", "Screenplay".
        public let role: String?
        public let credit: Credit
    }

    /// The cast, then the crew, in the server's order, each person once.
    public var people: [Person] {
        var seen: Set<String> = []
        return (details?.credits ?? []).compactMap { credit in
            guard seen.insert(credit.personID).inserted else { return nil }
            return Person(id: credit.personID, name: credit.name, role: Self.role(of: credit), credit: credit)
        }
    }

    /// Where `person`'s picture is, covering `pixelSize`, or nil without one.
    public func pictureURL(of person: Person, pixelSize: CGSize) -> URL? {
        images?.url(for: person.credit, pixelSize: pixelSize)
    }

    private static func role(of credit: Credit) -> String? {
        switch credit.kind {
        case .actor, .guestStar: credit.role
        case .director: "Director"
        case .writer: credit.role ?? "Writer"
        case .producer: credit.role ?? "Producer"
        case .composer: "Composer"
        case .creator: "Creator"
        case .other(let kind): credit.role ?? kind
        }
    }

    // MARK: About

    /// "Drama, Science Fiction", under the title on the About tile.
    public var genres: String? {
        item.genres.isEmpty ? nil : item.genres.joined(separator: ", ")
    }

    /// The overview, the tagline over it where there's one.
    public var overview: String? {
        item.overview
    }

    public var tagline: String? {
        details?.tagline
    }

    /// A score, as an About tile shows it: "94%" and "Critics".
    public struct Rating: Identifiable, Hashable {
        public let value: String
        public let label: String
        public var id: String { label }
    }

    /// The scores About shows beside the overview: the community's, out of 10, and critics', out of 100.
    public var ratings: [Rating] {
        var ratings: [Rating] = []
        if let community = item.communityRating {
            ratings.append(Rating(value: community.formatted(.number.precision(.fractionLength(1))), label: "Community Rating"))
        }
        if let critics = details?.criticRating {
            ratings.append(Rating(value: "\(Int(critics.rounded()))%", label: "Critics"))
        }
        return ratings
    }

    // MARK: Facts

    /// A column of facts at the page's end, such as Information: a title, and labeled values.
    public struct Column: Identifiable, Hashable {
        public let title: String
        public let facts: [Fact]
        public var id: String { title }
    }

    /// One fact in a column: "Released" and "November 10, 2016".
    public struct Fact: Identifiable, Hashable {
        public let label: String
        public let value: String
        public var id: String { label }
    }

    /// The block at the page's end: Information, Languages, Accessibility and the file, each only with
    /// something to say.
    public var columns: [Column] {
        [information, languages, accessibility, file].compactMap { $0 }.filter { !$0.facts.isEmpty }
    }

    private var information: Column? {
        var facts: [Fact] = []
        if let studios = details?.studios, !studios.isEmpty {
            facts.append(Fact(label: studios.count == 1 ? "Studio" : "Studios", value: studios.joined(separator: ", ")))
        }
        if let released = details?.releaseDate {
            // A day, which the server gives as midnight in UTC.
            facts.append(Fact(label: "Released", value: released.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: .gmt))))
        } else if let year = item.productionYear {
            facts.append(Fact(label: "Released", value: String(year)))
        }
        if let runtime = item.runtime {
            facts.append(Fact(label: "Run Time", value: runtime.formatted(.units(allowed: [.hours, .minutes], width: .narrow))))
        }
        if let rating = item.officialRating { facts.append(Fact(label: "Rated", value: rating)) }
        if let genres { facts.append(Fact(label: "Genres", value: genres)) }
        if let countries = details?.countries, !countries.isEmpty {
            facts.append(Fact(label: "Region of Origin", value: countries.joined(separator: ", ")))
        }
        return Column(title: "Information", facts: facts)
    }

    /// The audio tracks and subtitles, by language: "English (Dolby TrueHD · Dolby Atmos · 7.1)".
    private var languages: Column? {
        guard let version = details?.version else { return nil }
        var facts: [Fact] = []
        let audio = version.audio.map { track in
            let format = [track.formatName, track.spatialAudio == .dolbyAtmos ? "Dolby Atmos" : track.spatialAudio == .dtsX ? "DTS:X" : nil, track.surroundName]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            let name = languageName(track.language) ?? track.title
            return format.isEmpty ? name : "\(name) (\(format))"
        }
        if !audio.isEmpty { facts.append(Fact(label: "Audio", value: audio.joined(separator: ", "))) }
        let subtitles = version.subtitles.map { track in
            let kinds = [track.isForHearingImpaired ? "SDH" : nil, track.isForced ? "Forced" : nil].compactMap { $0 }
            let name = languageName(track.language) ?? track.title
            return kinds.isEmpty ? name : "\(name) (\(kinds.joined(separator: ", ")))"
        }
        if !subtitles.isEmpty { facts.append(Fact(label: "Subtitles", value: subtitles.joined(separator: ", "))) }
        return Column(title: "Languages", facts: facts)
    }

    /// What the badges mean, as the TV app explains them, for those the item has.
    private var accessibility: Column? {
        guard let subtitles = details?.version?.subtitles else { return nil }
        var facts: [Fact] = []
        if subtitles.contains(where: \.isForHearingImpaired) {
            facts.append(Fact(
                label: "SDH",
                value: "Subtitles for the deaf and hard of hearing (SDH) refer to subtitles in the original language with the addition of relevant non-dialogue information."
            ))
        } else if subtitles.contains(where: { !$0.isForced }) {
            facts.append(Fact(
                label: "CC",
                value: "Closed captions refer to subtitles in the available language with the addition of relevant non-dialogue information."
            ))
        }
        return Column(title: "Accessibility", facts: facts)
    }

    /// The file Play plays: its picture, dynamic range, main audio, and how it's stored.
    private var file: Column? {
        guard let version = details?.version else { return nil }
        var facts: [Fact] = []
        if let video = version.video {
            facts.append(Fact(label: "Video", value: video.description))
            if video.dynamicRange != .sdr { facts.append(Fact(label: "Dynamic Range", value: video.dynamicRange.description)) }
            if let bitrate = MediaVersion.bitrateName(video.bitrate) { facts.append(Fact(label: "Video Bitrate", value: bitrate)) }
        }
        if let audio = version.mainAudio {
            facts.append(Fact(label: "Audio", value: [languageName(audio.language), audio.description].compactMap { $0 }.joined(separator: " · ")))
        }
        let stored = [version.containerName, version.sizeName, MediaVersion.bitrateName(version.bitrate)].compactMap { $0 }
        if !stored.isEmpty { facts.append(Fact(label: "File", value: stored.joined(separator: " · "))) }
        return Column(title: "File", facts: facts)
    }
}
