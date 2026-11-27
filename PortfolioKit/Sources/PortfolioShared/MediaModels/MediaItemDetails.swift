import Foundation

/// What an item's page shows beyond its card: who made it and is in it, where and when it's from, and
/// its file.
public struct MediaItemDetails: Hashable, Sendable {
    /// The cast, then the crew, in the server's order.
    public let credits: [Credit]
    public let studios: [String]
    /// When it first came out.
    public let releaseDate: Date?
    /// The countries it was made in.
    public let countries: [String]
    public let tagline: String?
    /// Critics' score out of 100, such as Rotten Tomatoes'.
    public let criticRating: Double?
    /// Its first version, the one Play plays, if the server knows its file.
    public let version: MediaVersion?

    public init(
        credits: [Credit] = [],
        studios: [String] = [],
        releaseDate: Date? = nil,
        countries: [String] = [],
        tagline: String? = nil,
        criticRating: Double? = nil,
        version: MediaVersion? = nil
    ) {
        self.credits = credits
        self.studios = studios
        self.releaseDate = releaseDate
        self.countries = countries
        self.tagline = tagline
        self.criticRating = criticRating
        self.version = version
    }
}
