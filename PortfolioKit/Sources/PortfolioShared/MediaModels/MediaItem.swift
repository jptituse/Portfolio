/// A browsable or playable item: a movie, a series, an episode and so on.
public struct MediaItem: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case movie
        case series
        case season
        case episode
        case boxSet
        case folder
        /// Any other item type, kept as the server's raw value.
        case other(String)
    }

    public let id: String
    public let name: String
    public let kind: Kind
    public let overview: String?
    public let productionYear: Int?
    public let runtime: Duration?
    /// Content rating, such as `PG-13`.
    public let officialRating: String?
    /// Audience score on a 0–10 scale.
    public let communityRating: Double?
    public let genres: [String]
    /// The item's own images by kind, each the server's reference to it. They're opaque to the UI: the
    /// server integration that produced the item resolves them into URLs (`MediaImageResolver`). A
    /// reference changes whenever its image does, so it doubles as a cache key. An episode shows its
    /// show's images where it has none of its own (`image(_:)`).
    public let images: [MediaImageKind: String]
    /// The shape of the item's primary image, width over height, if the server knows it: a movie
    /// poster is about 0.67, an episode's still about 1.78.
    public let primaryImageAspectRatio: Double?
    public let userData: UserData
    /// Where it sits in its show, if it's an episode.
    public let episode: EpisodeInfo?

    public init(
        id: String,
        name: String,
        kind: Kind,
        overview: String? = nil,
        productionYear: Int? = nil,
        runtime: Duration? = nil,
        officialRating: String? = nil,
        communityRating: Double? = nil,
        genres: [String] = [],
        images: [MediaImageKind: String] = [:],
        primaryImageAspectRatio: Double? = nil,
        userData: UserData = UserData(),
        episode: EpisodeInfo? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.overview = overview
        self.productionYear = productionYear
        self.runtime = runtime
        self.officialRating = officialRating
        self.communityRating = communityRating
        self.genres = genres
        self.images = images
        self.primaryImageAspectRatio = primaryImageAspectRatio
        self.userData = userData
        self.episode = episode
    }
}

extension MediaItem {
    /// The item's `kind` image, and the item it belongs to: its own, or for an episode without one, its
    /// show's. An episode with backdrops of its own shows only those.
    public func image(_ kind: MediaImageKind) -> (ownerID: ID, tag: String)? {
        if let tag = images[kind] { return (id, tag) }
        guard let episode, let seriesID = episode.seriesID else { return nil }
        if case .backdrop = kind, images[.backdrop()] != nil { return nil }
        return episode.seriesImages[kind].map { (seriesID, $0) }
    }

    /// Whether the item shows a `kind` image, its own or its show's.
    public func hasImage(_ kind: MediaImageKind) -> Bool {
        image(kind) != nil
    }
}
