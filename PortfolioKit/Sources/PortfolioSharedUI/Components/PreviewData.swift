import Foundation
import PortfolioShared
import PortfolioSharedJellyfinClient

extension MediaItem {
    /// Sample movies, enough of them to overflow a row so that it scrolls.
    // FIXME: Only previews should need these once the section views load their rows from the server
    // (#10, #11). Move them into the DEBUG block below then.
    public static let samples: [MediaItem] = (1...20).map { number in
        MediaItem(
            id: "sample-movie-\(number)",
            name: "Sample Movie \(number)",
            kind: .movie,
            overview: "A sample used to try the browse, carousel and detail navigation before real "
                + "content arrives from the server.",
            productionYear: 2000 + number,
            runtime: .seconds(5400 + number * 420),
            officialRating: "PG-13",
            genres: ["Drama", "Science Fiction"]
        )
    }
}

extension RelatedMediaGroup {
    // FIXME: Only previews should need this once the section views load their groups from the server
    // (#10, #11). Move it into the DEBUG block below then.
    public static let sample = RelatedMediaGroup(id: "sample", title: "Sample Movies", items: MediaItem.samples)
}

#if DEBUG
extension UserSession {
    /// A session for previews and the debug sign-in. Its server doesn't exist.
    static let preview = UserSession(
        server: ServerInfo(
            id: "preview-server",
            name: "Preview Server",
            version: "10.11.2",
            url: URL(string: "http://preview.invalid:8096")!
        ),
        user: User(id: "preview-user", name: "Preview User", serverID: "preview-server", primaryImageTag: nil),
        accessToken: "preview-token"
    )
}

extension JellyfinServerClient {
    /// A client for previews.
    static let preview = JellyfinServerClient(
        identity: ClientIdentity(clientName: "Portfolio", version: "1.0", deviceName: "Preview", deviceID: "preview")
    )
}

extension SessionManager {
    /// A session manager with no profile open for previews, keeping anything saved apart from the
    /// app's own.
    static func preview() -> SessionManager {
        SessionManager(store: MediaServerStore(storage: KeychainStorage(service: "preview")), authority: JellyfinServerClient.preview)
    }
}

extension CurrentProfileViewModel {
    /// For previews of the main UI. No profile is open, so there's nobody to show.
    public static func preview() -> CurrentProfileViewModel {
        CurrentProfileViewModel(client: .preview, sessionManager: .preview())
    }
}

extension LibrariesViewModel {
    /// For previews and tests of the main navigation: `libraries`, arranged as the server's would be.
    /// They aren't loaded from anywhere.
    public static func preview(libraries: [Library] = []) -> LibrariesViewModel {
        let viewModel = LibrariesViewModel(client: .preview, session: nil)
        viewModel.show(libraries)
        return viewModel
    }
}

extension HomeViewModel {
    /// For previews of Home. Its server doesn't exist, so it shows that it couldn't be reached.
    public static func preview() -> HomeViewModel {
        HomeViewModel(client: .preview, session: .preview)
    }
}
#endif
