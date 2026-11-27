import CoreGraphics
import Foundation
import Observation
import PortfolioShared
import PortfolioSharedJellyfinClient

/// Search: what the profile's server has whose title, or for people whose name, matches what's typed,
/// in the chosen filter (`SearchFilter`), updating as it's typed. Top Results is a grid of movies, shows,
/// music videos and collections together, with the episodes and people found in rows below it; a kind's
/// filter is a grid of that kind; a genre's, a grid of what's in it. The genres are the server's. Only
/// the filters with anything in them show, as Top Results finds them for the text (`availability`), so
/// searching another filter asks Top Results too, once per text.
///
/// Each change to the text waits a moment for the next key (`typingPause`), then asks the server for
/// the chosen filter, a newer search cancelling one on its way. What was found stays until the next
/// answer arrives, so nothing blanks while typing; clearing the text clears it at once. A filter is
/// chosen once focus rests on it (`settleDelay`), or at once when it's selected, and searched at once;
/// what each filter found for the text is kept, so going back to one shows it at once. The searches are
/// the view model's own, not a view's task's.
@MainActor
@Observable
public final class SearchViewModel {
    /// What's typed in the search field. Changing it searches once typing pauses.
    public var text = "" {
        didSet { if text != oldValue { textChanged() } }
    }
    /// The filter chosen: the one showing, or about to once its search is answered.
    public private(set) var chosenFilter = SearchFilter.topResults
    /// The server's genres, each a filter after the kinds'.
    public private(set) var genres: [Genre] = []
    /// What the server found for the last search it answered.
    public private(set) var results = SearchResults()
    /// What Top Results found for the text showing, which says which filters have anything in them.
    private(set) var availability: SearchResults?
    /// What `results` were found for, or nil before any search, or once the text is cleared.
    public private(set) var resultsTerm: String?
    /// The filter `results` were found in.
    public private(set) var resultsFilter = SearchFilter.topResults
    /// Why the last search failed, if it did.
    public private(set) var failure: String?
    /// Where the items' artwork and people's pictures come from: the profile's server.
    public let images: (any MediaImageResolver)?

    @ObservationIgnored private let client: JellyfinServerClient
    @ObservationIgnored private let session: UserSession?
    @ObservationIgnored private let userDataUpdates: UserDataUpdates?
    @ObservationIgnored private let typingPause: Duration
    @ObservationIgnored private let settleDelay: Duration
    @ObservationIgnored private let limit: Int
    @ObservationIgnored private let rowLimit: Int
    /// The search waiting for typing to pause, or on its way to the server.
    @ObservationIgnored private var searching: Task<Void, Never>?
    /// Focus resting on a filter, before it's chosen.
    @ObservationIgnored private var settling: Task<Void, Never>?
    @ObservationIgnored private var genresLoad: Task<Void, Never>?
    /// What each filter found for `foundTerm`.
    @ObservationIgnored private var found: [SearchFilter: SearchResults] = [:]
    @ObservationIgnored private var foundTerm: String?
    @ObservationIgnored private var cards: [MediaItem.ID: MediaCardViewModel] = [:]
    /// The sizes artwork is fetched at, in pixels: a poster, a still, the screen and a logo.
    @ObservationIgnored private var artworkSizes: (poster: CGSize, still: CGSize, screen: CGSize, logo: CGSize)?

    init(
        client: JellyfinServerClient,
        session: UserSession?,
        userDataUpdates: UserDataUpdates? = nil,
        typingPause: Duration = .milliseconds(300),
        settleDelay: Duration = .milliseconds(100),
        limit: Int = 60,
        rowLimit: Int = 24
    ) {
        self.client = client
        self.session = session
        self.userDataUpdates = userDataUpdates
        self.typingPause = typingPause
        self.settleDelay = settleDelay
        self.limit = limit
        self.rowLimit = rowLimit
        images = session.map { JellyfinImageResolver(server: $0.server) }
    }

    // MARK: What it shows

    /// The filters with anything in them for the text showing, in order: Top Results, each kind that
    /// found anything, then the genres of what was found. The filter chosen stays, so it's never hidden
    /// while it shows, found anything or not.
    public var filters: [SearchFilter] {
        let kinds = SearchFilter.kinds.filter { $0 == .topResults || $0 == chosenFilter || availability?.kinds.contains($0) == true }
        let found = genres.filter { .genre($0) == chosenFilter || availability?.genres.contains($0.name) == true }
        return kinds + found.map(SearchFilter.genre)
    }

    public func title(of filter: SearchFilter) -> String {
        switch filter {
        case .topResults: String(localized: "Top Results")
        case .movies: String(localized: "Movies")
        case .shows: String(localized: "TV Shows")
        case .musicVideos: String(localized: "Music Videos")
        case .collections: String(localized: "Collections")
        case .episodes: String(localized: "Episodes")
        case .people: String(localized: "People")
        case .genre(let genre): genre.name
        }
    }

    /// Whether the filters show: once something's typed.
    public var showsFilters: Bool {
        !Self.term(text).isEmpty
    }

    /// The grid: the items found, or none in People's filter, which is all people.
    public var items: [MediaItem] { results.items }
    /// The episodes found, in a row below Top Results' grid.
    public var episodes: [MediaItem] { results.episodes }
    /// The people found: a row below Top Results' grid, or the grid in People's filter.
    public var people: [Person] { results.people }

    /// Why nothing shows, once a search has been answered: it failed, or found nothing.
    public var message: String? {
        if let failure { return failure }
        guard let resultsTerm, results.isEmpty else { return nil }
        return String(localized: "Nothing matches “\(resultsTerm)”.")
    }

    /// Names of what was found to finish what's typed with, the best first: the items', then the
    /// people's.
    public var suggestions: [String] {
        var seen: Set<String> = []
        let names = results.items.map(\.name) + results.people.map(\.name)
        return Array(names.filter { seen.insert($0.lowercased()).inserted }.prefix(Self.suggestionCount))
    }

    /// The shape an item's poster is drawn in.
    public enum PosterShape: Sendable {
        /// A movie poster's, 2:3.
        case poster
        /// A video's still, 16:9.
        case still
    }

    /// The shape of the grid's posters: stills for episodes and music videos on their own, posters for
    /// anything else, so music videos among other titles keep the grid even.
    public var gridShape: PosterShape {
        switch resultsFilter {
        case .episodes, .musicVideos: .still
        default: .poster
        }
    }

    /// The shape `item`'s poster is drawn in, in the grid or a row.
    public func shape(of item: MediaItem) -> PosterShape {
        item.kind == .episode ? .still : gridShape
    }

    // MARK: Searching

    /// Loads the server's genres for the filters, once; again if that failed.
    public func loadGenres() {
        guard genresLoad == nil, let session else { return }
        genresLoad = Task {
            if let found = try? await client.searchGenres(for: session) {
                if found != genres { genres = found }
            } else {
                genresLoad = nil
            }
        }
    }

    /// Focus moved to a filter: it's chosen once focus rests there.
    public func filterFocused(_ filter: SearchFilter) {
        settling?.cancel()
        settling = Task { [settleDelay] in
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled else { return }
            choose(filter)
        }
    }

    /// A filter was selected: it's chosen at once.
    public func filterSelected(_ filter: SearchFilter) {
        settling?.cancel()
        choose(filter)
    }

    private func choose(_ filter: SearchFilter) {
        guard filter != chosenFilter else { return }
        chosenFilter = filter
        let term = Self.term(text)
        guard !term.isEmpty else { return }
        searching?.cancel()
        searching = nil
        if foundTerm == term, let known = found[filter] {
            show(known, for: term, in: filter)
            failure = nil
        } else {
            searching = Task { await search(for: term, in: filter) }
        }
    }

    private func textChanged() {
        let term = Self.term(text)
        searching?.cancel()
        searching = nil
        guard !term.isEmpty else {
            results = SearchResults()
            resultsTerm = nil
            failure = nil
            availability = nil
            found = [:]
            foundTerm = nil
            return
        }
        // Back to what's showing, or only a space added or taken away.
        if term == resultsTerm, resultsFilter == chosenFilter, failure == nil { return }
        let filter = chosenFilter
        searching = Task { [typingPause] in
            try? await Task.sleep(for: typingPause)
            guard !Task.isCancelled else { return }
            await search(for: term, in: filter)
        }
    }

    /// Searches `filter` for `term`, and Top Results too, unless it's known, for which filters have
    /// anything in them.
    private func search(for term: String, in filter: SearchFilter) async {
        guard let session else { return }
        let asksTopResults = filter != .topResults && (foundTerm != term || found[.topResults] == nil)
        do {
            async let top = topResults(for: term, if: asksTopResults, session: session)
            let answer = try await client.search(term, in: filter, for: session, limit: limit, rowLimit: rowLimit)
            let topAnswer = try await top
            guard !Task.isCancelled else { return }
            if foundTerm != term {
                found = [:]
                foundTerm = term
            }
            found[filter] = answer
            if let topAnswer { found[.topResults] = topAnswer }
            let known = found[.topResults]
            if availability != known { availability = known }
            show(answer, for: term, in: filter)
            failure = nil
        } catch {
            // A newer search took over.
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            show(SearchResults(), for: term, in: filter)
            availability = nil
            failure = LoadingFailure.message(for: error, server: session.server.name, activity: "searching")
        }
        searching = nil
    }

    private func topResults(for term: String, if asked: Bool, session: UserSession) async throws -> SearchResults? {
        guard asked else { return nil }
        return try await client.search(term, in: .topResults, for: session, limit: limit, rowLimit: rowLimit)
    }

    /// Shows `answer`, keeping the cards of items still among it, so a poster that stays doesn't load
    /// again.
    private func show(_ answer: SearchResults, for term: String, in filter: SearchFilter) {
        let kept = Set((answer.items + answer.episodes).map(\.id))
        cards = cards.filter { kept.contains($0.key) }
        if results != answer { results = answer }
        resultsTerm = term
        if resultsFilter != filter { resultsFilter = filter }
        // A music video's poster is a still on its own and a poster among other titles.
        cards.values.forEach(setArtworkSizes)
    }

    /// What's searched for: `text` without spaces around it.
    private static func term(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// How many names are suggested.
    static let suggestionCount = 6

    // MARK: Cards

    /// Sets the sizes artwork is fetched at: a poster and a still as the grid and rows draw them, the
    /// screen (where a full-screen card's artwork goes) and a logo, in points, at `scale`.
    public func setArtworkSizes(poster: CGSize, still: CGSize, screen: CGSize, logo: CGSize, scale: CGFloat) {
        artworkSizes = (
            RemoteImageViewModel.requestSize(for: poster, scale: scale),
            RemoteImageViewModel.requestSize(for: still, scale: scale),
            RemoteImageViewModel.requestSize(for: screen, scale: scale),
            RemoteImageViewModel.requestSize(for: logo, scale: scale)
        )
        cards.values.forEach(setArtworkSizes)
    }

    /// An item's poster, which grows into its full-screen card.
    public func card(for item: MediaItem) -> MediaCardViewModel {
        if let card = cards[item.id] { return card }
        let card = MediaCardViewModel(item: item, images: images, userDataUpdates: userDataUpdates)
        setArtworkSizes(of: card)
        cards[item.id] = card
        return card
    }

    /// What an episode is, under its still, since the still shows its show's logo: "Severance · S1, E5".
    /// Nil for anything else.
    public func caption(of item: MediaItem) -> String? {
        guard let episode = item.episode else { return nil }
        let parts = [episode.seriesName, episode.longLabel].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Where `person`'s picture is, covering `pixelSize`, or nil without one.
    public func pictureURL(of person: Person, pixelSize: CGSize) -> URL? {
        images?.url(for: person, pixelSize: pixelSize)
    }

    /// A poster got focus: its card loads its landscape art and draws it, unseen, under its poster, so
    /// it's there to cross-fade into as the card grows to full screen. Only the focused card's is kept,
    /// so one screen-sized image is in memory.
    public func posterFocused(_ item: MediaItem) {
        let focused = card(for: item)
        for card in cards.values where card.isWarm && card !== focused {
            card.isWarm = false
        }
        if !focused.isWarm { focused.isWarm = true }
    }

    private func setArtworkSizes(of card: MediaCardViewModel) {
        guard let artworkSizes else { return }
        let poster = shape(of: card.item) == .still ? artworkSizes.still : artworkSizes.poster
        // Only what changed, so a card isn't drawn again for nothing.
        if card.posterArtworkSize != poster { card.posterArtworkSize = poster }
        if card.landscapeArtworkSize != artworkSizes.screen { card.landscapeArtworkSize = artworkSizes.screen }
        if card.logoArtworkSize != artworkSizes.logo { card.logoArtworkSize = artworkSizes.logo }
    }
}
