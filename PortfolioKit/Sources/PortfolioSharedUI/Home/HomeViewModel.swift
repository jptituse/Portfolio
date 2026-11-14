import Observation
import PortfolioShared
import PortfolioSharedJellyfinClient

/// The open profile's Home: a banner of what was added most recently, then Continue Watching (what
/// they're partway through, and the next episode of each show they're watching), then the latest of
/// each library. It loads again each time it's shown, so it keeps up with the server.
@MainActor
@Observable
public final class HomeViewModel {
    /// The items the banner goes through: the first few added most recently.
    // FIXME: Choose these with the recommendations (#30), rather than just the newest.
    public private(set) var bannerItems: [MediaItem] = []
    /// The rows under the banner: Continue Watching, then the latest of each library. Empty until
    /// they've loaded, or if there's nothing to show.
    public private(set) var groups: [RelatedMediaGroup] = []
    /// Whether it's loading with nothing to show yet. Loading again keeps what's showing until the new
    /// rows arrive, so it never blanks Home or shifts it while it does.
    public private(set) var isLoading = false
    /// Why there's nothing to show: nothing has been added yet, or loading failed.
    public private(set) var message: String?
    /// Whether loading failed, so it can be tried again.
    public private(set) var canRetry = false
    /// Where the items' artwork comes from: the profile's server.
    public let images: (any MediaImageResolver)?

    @ObservationIgnored private let client: JellyfinServerClient
    @ObservationIgnored private let session: UserSession?
    /// The load under way. It's Home's own, so the view that asked for it going away doesn't cancel it.
    @ObservationIgnored private var loading: Task<Void, Never>?

    init(client: JellyfinServerClient, session: UserSession?) {
        self.client = client
        self.session = session
        images = session.map { JellyfinImageResolver(server: $0.server) }
    }

    /// Loads Home from the server, and returns once it has loaded or failed: each time it's shown, and
    /// when someone tries again. Asking while it loads waits for that load.
    ///
    /// Views ask from `task`, which SwiftUI can cancel and start again when it replaces a view: Home
    /// opening could cancel its own load against a server slow enough to still be answering, and
    /// stay empty. So the load carries on, whatever happens to the caller.
    public func load() async {
        await startLoading().value
    }

    private func startLoading() -> Task<Void, Never> {
        if let loading { return loading }
        let load = Task {
            await performLoad()
            loading = nil
        }
        loading = load
        return load
    }

    private func performLoad() async {
        guard let session else { return }
        if bannerItems.isEmpty && groups.isEmpty {
            isLoading = true
            message = nil
            canRetry = false
        }
        defer { isLoading = false }
        do {
            async let banner = client.recentlyAdded(for: session, limit: Self.bannerCount)
            async let resume = client.resumeItems(for: session)
            async let nextUp = client.nextUp(for: session)
            async let libraries = client.libraries(for: session)
            // Without the user's settings, every library has a Latest row.
            async let leftOut = (try? await client.librariesLeftOutOfLatest(for: session)) ?? []
            let continueWatching = Self.continueWatching(resume: try await resume, nextUp: try await nextUp)
            let latest = await latestRows(for: try await libraries, leavingOut: await leftOut, session: session)
            let bannerItems = try await banner
            let groups = (continueWatching.map { [$0] } ?? []) + latest
            // Unchanged rows stay as they are, so the browsing view keeps its place.
            if bannerItems != self.bannerItems { self.bannerItems = bannerItems }
            if groups != self.groups { self.groups = groups }
            message = bannerItems.isEmpty && groups.isEmpty ? String(localized: "Nothing has been added to your libraries yet.") : nil
            canRetry = false
        } catch {
            // Rows already showing stay, with why they couldn't be brought up to date.
            message = LoadingFailure.message(for: error, server: session.server.name, activity: "loading what's new")
            canRetry = true
        }
    }

    /// What the user is partway through, most recently watched first, then the next episode of each
    /// show they're watching that they haven't started. Shows they're partway through an episode of
    /// already aren't listed twice.
    static func continueWatching(resume: [MediaItem], nextUp: [MediaItem]) -> RelatedMediaGroup? {
        let resumedIDs = Set(resume.map(\.id))
        let resumedShows = Set(resume.compactMap { $0.episode?.seriesID })
        let upNext = nextUp.filter { item in
            guard !resumedIDs.contains(item.id) else { return false }
            guard let show = item.episode?.seriesID else { return true }
            return !resumedShows.contains(show)
        }
        let items = resume + upNext
        guard !items.isEmpty else { return nil }
        return RelatedMediaGroup(id: continueWatchingID, title: String(localized: "Continue Watching"), items: items, style: .inProgress)
    }

    /// A row of the latest items of each library that has them, in the user's order, leaving out the
    /// libraries they've left out of their latest items, and those whose items aren't added as such:
    /// collections, playlists and Live TV. A library whose latest can't be loaded is left out.
    private func latestRows(for libraries: [Library], leavingOut leftOut: Set<String>, session: UserSession) async -> [RelatedMediaGroup] {
        let shown = libraries.filter { !leftOut.contains($0.id) && Self.hasLatestItems($0.kind) }
        let rows = await withTaskGroup(of: (Int, RelatedMediaGroup?).self) { group in
            for (index, library) in shown.enumerated() {
                group.addTask { [client] in
                    let items = (try? await client.recentlyAdded(for: session, in: library.id, limit: Self.latestCount)) ?? []
                    let row = items.isEmpty ? nil : RelatedMediaGroup(
                        id: "latest-\(library.id)",
                        title: String(localized: "Latest \(library.name)"),
                        items: items
                    )
                    return (index, row)
                }
            }
            var rows: [(Int, RelatedMediaGroup?)] = []
            for await row in group { rows.append(row) }
            return rows
        }
        return rows.sorted { $0.0 < $1.0 }.compactMap(\.1)
    }

    static func hasLatestItems(_ kind: Library.Kind) -> Bool {
        switch kind {
        case .collections, .playlists, .liveTV: false
        default: true
        }
    }

    static let continueWatchingID = "continue-watching"
    /// How many of the newest items the banner goes through.
    static let bannerCount = 8
    /// How many items each Latest row has.
    static let latestCount = 16
}
