/// Where an episode sits in its show.
public struct EpisodeInfo: Hashable, Sendable {
    public let seriesName: String?
    public let seriesID: String?
    public let seasonNumber: Int?
    public let episodeNumber: Int?

    public init(seriesName: String? = nil, seriesID: String? = nil, seasonNumber: Int? = nil, episodeNumber: Int? = nil) {
        self.seriesName = seriesName
        self.seriesID = seriesID
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
    }
}
