import PortfolioShared

extension EpisodeInfo {
    /// "S1E5", or "E5" without a season, or nil without an episode number.
    var shortLabel: String? {
        guard let episodeNumber else { return nil }
        guard let seasonNumber else { return "E\(episodeNumber)" }
        return "S\(seasonNumber)E\(episodeNumber)"
    }

    /// "S1, E5" for the fifth episode of the first season, as the TV app leads an episode's overview with
    /// it; "E5" without a season.
    var longLabel: String? {
        guard let episodeNumber else { return nil }
        guard let seasonNumber else { return "E\(episodeNumber)" }
        return "S\(seasonNumber), E\(episodeNumber)"
    }
}
