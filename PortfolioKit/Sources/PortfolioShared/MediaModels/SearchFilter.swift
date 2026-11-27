/// What a search looks for: its best matches of every kind (`topResults`), one kind, or what's in a
/// genre.
public enum SearchFilter: Hashable, Sendable {
    /// Movies, shows, music videos and collections together, the best first, with the episodes and
    /// people found besides.
    case topResults
    case movies
    case shows
    case musicVideos
    case collections
    case episodes
    case people
    /// Movies, shows, music videos and collections in a genre.
    case genre(Genre)

    /// Every filter of a kind, in order, before any genre's.
    public static let kinds: [SearchFilter] = [.topResults, .movies, .shows, .musicVideos, .collections, .episodes, .people]
}
