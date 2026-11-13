import CoreGraphics
import Foundation
import Observation
import PortfolioShared
import PortfolioSharedJellyfinClient

/// One library view: its sidebar items (Recently Added, all its items, and its genres) and a grid of
/// the chosen sidebar item's items, which loads a page at a time as someone scrolls down.
///
/// The grid follows focus on the sidebar items, once focus has rested on one for a moment
/// (`settleDelay`), so passing over sidebar items doesn't swap the grid back and forth. To make
/// switching quick, every sidebar item's first page (a small one) loads as soon as the genres are
/// known, and the first posters of the focused sidebar item and the ones beside it load as soon as
/// focus reaches it. Each sidebar item's items are kept, so going back to one shows it at once, and
/// loads its first page again if it's been a while (`refreshAfter`). The grid showing stays until the
/// next one has loaded.
///
/// A poster getting focus has its card load its landscape art, unseen, so it's there to cross-fade
/// into as the card grows to full screen.
@MainActor
@Observable
public final class LibraryViewModel {
    public let scope: LibraryScope
    /// The genres there are sidebar items for, by name.
    public private(set) var genres: [Genre] = []
    /// The sidebar item whose grid is showing.
    public private(set) var shownSidebarItem: LibrarySidebarItem = .recentlyAdded
    /// The sidebar item chosen last: the one showing, or the one about to once it has loaded.
    public private(set) var chosenSidebarItem: LibrarySidebarItem = .recentlyAdded
    /// Why the grid couldn't be loaded.
    public private(set) var failure: String?
    /// Where the items' artwork comes from: the profile's server.
    public let images: (any MediaImageResolver)?

    /// Each sidebar item's items loaded so far, and how many it has in all.
    private var loaded: [LibrarySidebarItem: LoadedItems] = [:]

    @ObservationIgnored private let client: JellyfinServerClient
    @ObservationIgnored private let session: UserSession?
    @ObservationIgnored private let pipeline: ImagePipeline
    @ObservationIgnored private let settleDelay: Duration
    @ObservationIgnored private let firstPageSize: Int
    @ObservationIgnored private let pageSize: Int
    @ObservationIgnored private let refreshAfter: Duration
    /// When each sidebar item's first page last loaded.
    @ObservationIgnored private var loadedAt: [LibrarySidebarItem: ContinuousClock.Instant] = [:]
    /// The focused sidebar item and the ones beside it, whose first posters load ahead.
    @ObservationIgnored private var nearbySidebarItems: Set<LibrarySidebarItem> = []
    /// Each sidebar item's first page while it loads, numbered so a load that's been replaced doesn't
    /// clear its replacement when it ends.
    @ObservationIgnored private var firstPageLoads: [LibrarySidebarItem: (number: Int, task: Task<Void, Never>)] = [:]
    @ObservationIgnored private var nextPageLoad: (number: Int, task: Task<Void, Never>)?
    @ObservationIgnored private var loadNumber = 0
    @ObservationIgnored private var genresLoad: Task<Void, Never>?
    @ObservationIgnored private var settling: Task<Void, Never>?
    @ObservationIgnored private var cards: [MediaItem.ID: MediaCardViewModel] = [:]
    /// The sizes artwork is fetched at, in pixels: a poster in the grid, the screen, and a logo.
    @ObservationIgnored private var artworkSizes: (poster: CGSize, screen: CGSize, logo: CGSize)?

    private struct LoadedItems: Equatable {
        var items: [MediaItem]
        var totalCount: Int
    }

    init(
        scope: LibraryScope,
        client: JellyfinServerClient,
        session: UserSession?,
        pipeline: ImagePipeline = .shared,
        settleDelay: Duration = .milliseconds(100),
        firstPageSize: Int = 24,
        pageSize: Int = 60,
        refreshAfter: Duration = .seconds(10)
    ) {
        self.scope = scope
        self.client = client
        self.session = session
        self.pipeline = pipeline
        self.settleDelay = settleDelay
        self.firstPageSize = firstPageSize
        self.pageSize = pageSize
        self.refreshAfter = refreshAfter
        images = session.map { JellyfinImageResolver(server: $0.server) }
    }

    // MARK: What it shows

    public var title: String { scope.title }

    /// The sidebar items before the genres.
    public var mainSidebarItems: [LibrarySidebarItem] { [.recentlyAdded, .all] }

    /// Every sidebar item, in order.
    private var allSidebarItems: [LibrarySidebarItem] { mainSidebarItems + genres.map(LibrarySidebarItem.genre) }

    public func title(of sidebarItem: LibrarySidebarItem) -> String {
        switch sidebarItem {
        case .recentlyAdded: String(localized: "Recently Added")
        case .all: String(localized: "All \(scope.kind.pluralName)")
        case .genre(let genre): genre.name
        }
    }

    /// The items of the sidebar item showing, as far as they've loaded.
    public var items: [MediaItem] {
        loaded[shownSidebarItem]?.items ?? []
    }

    /// Whether the grid is waiting for its first items, with nothing to show yet.
    public var isLoading: Bool {
        loaded[shownSidebarItem] == nil && failure == nil
    }

    /// Why the grid is empty, if it is.
    public var message: String? {
        if let failure { return failure }
        guard let sidebarItem = loaded[shownSidebarItem], sidebarItem.items.isEmpty else { return nil }
        return String(localized: "Nothing here yet.")
    }

    /// The shape of the grid's posters, width over height, which suits the library's kind.
    public var posterAspectRatio: Double { scope.kind.posterAspectRatio }

    // MARK: Loading

    /// Loads the genres and the chosen sidebar item's first page, then the first page of every other
    /// sidebar item not loaded yet, and returns once they've loaded or failed: each time the library is
    /// shown, so it keeps up with the server. What's showing stays meanwhile, and the chosen sidebar
    /// item shows as soon as it has loaded.
    public func load() async {
        async let genres: Void = loadGenres()
        let chosen = loadFirstPage(of: chosenSidebarItem)
        await genres
        let others = allSidebarItems.filter { loaded[$0] == nil }.map { loadFirstPage(of: $0) }
        await chosen.value
        for other in others { await other.value }
    }

    /// Focus moved to a sidebar item, or off the sidebar items (nil). The grid follows once focus rests
    /// there.
    public func sidebarItemFocused(_ sidebarItem: LibrarySidebarItem?) {
        // Moving into the grid leaves the chosen sidebar item as it is.
        guard let sidebarItem else { return }
        settling?.cancel()
        // The sidebar item and the ones beside it, where focus may go next: their first posters load
        // now, or once their first page has.
        let sidebarItems = allSidebarItems
        let index = sidebarItems.firstIndex(of: sidebarItem) ?? 0
        nearbySidebarItems = Set(sidebarItems[max(0, index - 1)...min(sidebarItems.count - 1, index + 1)] + [sidebarItem])
        for other in nearbySidebarItems {
            if let items = loaded[other]?.items {
                warmPosters(of: items)
            } else {
                _ = loadFirstPage(of: other)
            }
        }
        settling = Task { [settleDelay] in
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled else { return }
            choose(sidebarItem)
        }
    }

    /// A sidebar item was selected: it's chosen at once, without waiting for focus to rest.
    public func sidebarItemSelected(_ sidebarItem: LibrarySidebarItem) {
        settling?.cancel()
        choose(sidebarItem)
    }

    /// An item came on screen in the grid. Nearing the end of what's loaded, the next page loads.
    public func itemAppeared(_ item: MediaItem) {
        let sidebarItem = shownSidebarItem
        guard nextPageLoad == nil,
            let current = loaded[sidebarItem], current.items.count < current.totalCount,
            let index = current.items.firstIndex(where: { $0.id == item.id }),
            index >= current.items.count - Self.prefetchDistance else {
            return
        }
        let start = current.items.count
        loadNumber += 1
        let number = loadNumber
        let task = Task {
            defer { if nextPageLoad?.number == number { nextPageLoad = nil } }
            guard let session,
                let page = try? await client.items(sidebarItem, in: scope, startIndex: start, limit: pageSize, for: session),
                // Unless the sidebar item has started over meanwhile.
                var updated = loaded[sidebarItem], updated.items.count == start else {
                return
            }
            let known = Set(updated.items.map(\.id))
            updated.items += page.items.filter { !known.contains($0.id) }
            // A server that runs out early has no more to give.
            updated.totalCount = page.items.isEmpty ? updated.items.count : page.totalCount
            loaded[sidebarItem] = updated
        }
        nextPageLoad = (number, task)
    }

    private func choose(_ sidebarItem: LibrarySidebarItem) {
        guard sidebarItem != chosenSidebarItem else { return }
        chosenSidebarItem = sidebarItem
        nextPageLoad?.task.cancel()
        nextPageLoad = nil
        if loaded[sidebarItem] != nil {
            show(sidebarItem)
            // Loads its first page again to catch anything new, unless it has just loaded.
            if let loadedAt = loadedAt[sidebarItem], ContinuousClock.now - loadedAt < refreshAfter { return }
        }
        _ = loadFirstPage(of: sidebarItem)
    }

    private func show(_ sidebarItem: LibrarySidebarItem) {
        shownSidebarItem = sidebarItem
        failure = nil
    }

    private func loadFirstPage(of sidebarItem: LibrarySidebarItem) -> Task<Void, Never> {
        if let load = firstPageLoads[sidebarItem], !load.task.isCancelled { return load.task }
        loadNumber += 1
        let number = loadNumber
        let task = Task {
            await performFirstPageLoad(of: sidebarItem)
            if firstPageLoads[sidebarItem]?.number == number { firstPageLoads[sidebarItem] = nil }
        }
        firstPageLoads[sidebarItem] = (number, task)
        return task
    }

    private func performFirstPageLoad(of sidebarItem: LibrarySidebarItem) async {
        guard let session else { return }
        do {
            let page = try await client.items(sidebarItem, in: scope, startIndex: 0, limit: firstPageSize, for: session)
            loadedAt[sidebarItem] = .now
            if sidebarItem == chosenSidebarItem || nearbySidebarItems.contains(sidebarItem) {
                warmPosters(of: page.items)
            }
            let fresh = LoadedItems(items: page.items, totalCount: page.totalCount)
            if let current = loaded[sidebarItem], Array(current.items.prefix(firstPageSize)) == page.items {
                // Nothing new: whatever else has loaded stays, and so does the grid's place.
                loaded[sidebarItem]?.totalCount = page.totalCount
            } else if loaded[sidebarItem] != fresh {
                loaded[sidebarItem] = fresh
            }
            if sidebarItem == chosenSidebarItem { show(sidebarItem) }
        } catch is CancellationError {
            // Focus moved on, or the library stopped showing.
        } catch {
            // A sidebar item already loaded keeps what it has.
            guard sidebarItem == chosenSidebarItem, loaded[sidebarItem] == nil else { return }
            shownSidebarItem = sidebarItem
            failure = LoadingFailure.message(for: error, server: session.server.name, activity: "loading this library")
        }
    }

    private func loadGenres() async {
        if let genresLoad { return await genresLoad.value }
        let load = Task {
            if let session, let genres = try? await client.genres(in: scope, for: session), genres != self.genres {
                self.genres = genres
            }
            genresLoad = nil
        }
        genresLoad = load
        await load.value
    }

    // MARK: Ahead of time

    /// Loads a sidebar item's first posters into memory, so they show at once when the sidebar item
    /// does.
    private func warmPosters(of items: [MediaItem]) {
        for item in items.prefix(Self.postersWarmed) {
            warm(card(for: item).posterArtworkURL)
        }
    }

    /// A poster in the grid got focus: its card loads its landscape art and draws it, unseen, under its
    /// poster, so it's there to cross-fade into as the card grows to full screen. Adding it while the
    /// card moves would draw blank frames. Only the focused card's is kept, so one screen-sized image is
    /// in memory.
    public func posterFocused(_ item: MediaItem) {
        let focused = card(for: item)
        for card in cards.values where card.isWarm && card !== focused {
            card.isWarm = false
        }
        if !focused.isWarm { focused.isWarm = true }
    }

    private func warm(_ url: URL?) {
        guard let url, pipeline.cachedImage(for: url) == nil else { return }
        Task { [pipeline] in _ = try? await pipeline.image(for: url) }
    }

    // MARK: Cards

    /// Sets the sizes artwork is fetched at: a poster as the grid draws it, the screen (where a detail
    /// card's artwork goes) and a logo, in points, at `scale`.
    public func setArtworkSizes(poster: CGSize, screen: CGSize, logo: CGSize, scale: CGFloat) {
        artworkSizes = (
            RemoteImageViewModel.requestSize(for: poster, scale: scale),
            RemoteImageViewModel.requestSize(for: screen, scale: scale),
            RemoteImageViewModel.requestSize(for: logo, scale: scale)
        )
        cards.values.forEach(setArtworkSizes)
    }

    /// An item's poster in the grid.
    public func card(for item: MediaItem) -> MediaCardViewModel {
        if let card = cards[item.id] { return card }
        let card = MediaCardViewModel(item: item, images: images)
        setArtworkSizes(of: card)
        cards[item.id] = card
        return card
    }

    private func setArtworkSizes(of card: MediaCardViewModel) {
        guard let artworkSizes else { return }
        card.posterArtworkSize = artworkSizes.poster
        card.landscapeArtworkSize = artworkSizes.screen
        card.logoArtworkSize = artworkSizes.logo
    }

    /// How close to the end of what's loaded an item comes on screen before the next page loads.
    static let prefetchDistance = 20
    /// How many of a sidebar item's posters load ahead of it showing: about two screens' worth.
    static let postersWarmed = 16
}
