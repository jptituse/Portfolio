import Observation
import PortfolioShared
import PortfolioSharedJellyfinClient

/// The open profile's Home: what was added to their libraries most recently, with its artwork. It loads
/// again each time it's shown, so it keeps up with the server.
@MainActor
@Observable
public final class HomeViewModel {
    /// The rows to show. Empty until they've loaded, or if there's nothing to show.
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
        if groups.isEmpty {
            isLoading = true
            message = nil
            canRetry = false
        }
        defer { isLoading = false }
        do {
            let items = try await client.recentlyAdded(for: session)
            let groups = items.isEmpty ? [] : [RelatedMediaGroup(id: Self.recentlyAddedID, title: "Recently Added", items: items)]
            // Unchanged rows stay as they are, so the browsing view keeps its place.
            if groups != self.groups { self.groups = groups }
            message = items.isEmpty ? "Nothing has been added to your libraries yet." : nil
            canRetry = false
        } catch {
            // Rows already showing stay, with why they couldn't be brought up to date.
            message = LoadingFailure.message(for: error, server: session.server.name, activity: "loading what's new")
            canRetry = true
        }
    }

    static let recentlyAddedID = "recently-added"
}
