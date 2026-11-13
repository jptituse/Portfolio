import PortfolioShared

extension LibraryScope {
    /// The name it goes by: the kind's for every library of a kind, the library's own for one.
    public var title: String {
        switch self {
        case .library(let library): library.name
        case .kind(let kind): kind.pluralName
        }
    }

    /// An SF Symbol for it.
    public var systemImage: String {
        switch kind {
        case .movies: "film"
        case .tvShows: "tv"
        case .collections: "square.stack"
        case .playlists: "music.note.list"
        case .musicVideos: "music.note.tv"
        case .music: "music.note"
        case .homeVideos: "video"
        case .liveTV: "antenna.radiowaves.left.and.right"
        case .other("books"): "book"
        case .other("photos"): "photo.on.rectangle"
        case .mixed, .other: "folder"
        }
    }
}

extension Library.Kind {
    /// What its items are called, together: "Movies", "TV Shows" and so on.
    var pluralName: String {
        switch self {
        case .movies: String(localized: "Movies")
        case .tvShows: String(localized: "TV Shows")
        case .collections: String(localized: "Collections")
        case .playlists: String(localized: "Playlists")
        case .musicVideos: String(localized: "Music Videos")
        case .music: String(localized: "Albums")
        case .homeVideos: String(localized: "Videos")
        case .liveTV: String(localized: "Channels")
        case .other("books"): String(localized: "Books")
        case .other("photos"): String(localized: "Photos")
        case .mixed, .other: String(localized: "Items")
        }
    }

    /// The shape of its items' posters, width over height: a movie poster's, a video's, or an album's.
    var posterAspectRatio: Double {
        switch self {
        case .musicVideos, .homeVideos, .liveTV, .other("photos"): 16.0 / 9
        case .music: 1
        default: 2.0 / 3
        }
    }
}
