/// Where an episode sits in its show, and the show's images, which the episode shows where it has none
/// of its own.
public struct EpisodeInfo: Hashable, Sendable {
    public let seriesName: String?
    public let seriesID: String?
    public let seasonNumber: Int?
    public let episodeNumber: Int?
    /// Its season's name, such as "Season 1" or "Specials", as the server has it.
    public let seasonName: String?
    /// The show's images by kind, opaque like `MediaItem.images`: those the server says the episode
    /// shows, such as its show's backdrops and logo.
    public let seriesImages: [MediaImageKind: String]

    public init(
        seriesName: String? = nil,
        seriesID: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        seasonName: String? = nil,
        seriesImages: [MediaImageKind: String] = [:]
    ) {
        self.seriesName = seriesName
        self.seriesID = seriesID
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.seasonName = seasonName
        self.seriesImages = seriesImages
    }
}
