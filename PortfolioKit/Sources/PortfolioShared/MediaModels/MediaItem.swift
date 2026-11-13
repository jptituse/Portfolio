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
    /// The item's images by kind, each the server's reference to it. They're opaque to the UI: the
    /// server integration that produced the item resolves them into URLs (`MediaImageResolver`). A
    /// reference changes whenever its image does, so it doubles as a cache key.
    public let images: [MediaImageKind: String]
    /// The shape of the item's primary image, width over height, if the server knows it: a movie
    /// poster is about 0.67, an episode's still about 1.78.
    public let primaryImageAspectRatio: Double?
    public let userData: UserData

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
        userData: UserData = UserData()
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
    }
}
