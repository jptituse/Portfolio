/// A top-level library, such as Movies or Shows.
public struct Library: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case movies
        case tvShows
        case music
        case musicVideos
        case homeVideos
        case collections
        case playlists
        case liveTV
        /// A library that mixes content types (no collection type on the server).
        case mixed
        /// Any other collection type, kept as the server's raw value.
        case other(String)
    }

    public let id: String
    public let name: String
    public let kind: Kind
    /// The library's images by kind, opaque like `MediaItem.images`.
    public let images: [MediaImageKind: String]

    public init(id: String, name: String, kind: Kind, images: [MediaImageKind: String] = [:]) {
        self.id = id
        self.name = name
        self.kind = kind
        self.images = images
    }
}
