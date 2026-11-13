import Observation
import PortfolioShared
import PortfolioSharedJellyfinClient

/// The open profile's libraries, arranged for the main navigation. The standard kinds (Movies, TV Shows,
/// Collections, Playlists and Music Videos) each get one entry with every library of that kind
/// together. Libraries of any other kind come after, each on its own, and so does each library of a
/// standard kind that has several, such as "4K Movies" beside "Movies".
@MainActor
@Observable
public final class LibrariesViewModel {
    /// One entry per standard kind the profile has, in a fixed order.
    public private(set) var standard: [LibraryScope] = []
    /// Libraries on their own, in the server's order.
    public private(set) var special: [LibraryScope] = []

    @ObservationIgnored private let client: JellyfinServerClient
    @ObservationIgnored private let session: UserSession?
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var libraryViewModels: [LibraryScope: LibraryViewModel] = [:]

    init(client: JellyfinServerClient, session: UserSession?) {
        self.client = client
        self.session = session
    }

    /// Loads the libraries, and returns once they've loaded or failed. Libraries already listed stay
    /// if they can't be loaded again. Like Home's, the load carries on if the caller goes away.
    public func load() async {
        if let loading { return await loading.value }
        let load = Task {
            if let session, let libraries = try? await client.libraries(for: session) {
                show(libraries)
            }
            loading = nil
        }
        loading = load
        await load.value
    }

    func show(_ libraries: [Library]) {
        let (standard, special) = Self.arrange(libraries)
        if standard != self.standard { self.standard = standard }
        if special != self.special { self.special = special }
    }

    /// The view model of an entry's library view. It's kept, so coming back to a library finds it as
    /// it was left.
    public func viewModel(for scope: LibraryScope) -> LibraryViewModel {
        if let viewModel = libraryViewModels[scope] { return viewModel }
        let viewModel = LibraryViewModel(scope: scope, client: client, session: session)
        libraryViewModels[scope] = viewModel
        return viewModel
    }

    /// The kinds that get an entry of their own, combining their libraries, in the order they're listed.
    static let standardKinds: [Library.Kind] = [.movies, .tvShows, .collections, .playlists, .musicVideos]

    static func arrange(_ libraries: [Library]) -> (standard: [LibraryScope], special: [LibraryScope]) {
        let standard = standardKinds.filter { kind in libraries.contains { $0.kind == kind } }
        let special = libraries.filter { library in
            !standardKinds.contains(library.kind) || libraries.count { $0.kind == library.kind } > 1
        }
        return (standard.map(LibraryScope.kind), special.map(LibraryScope.library))
    }
}
