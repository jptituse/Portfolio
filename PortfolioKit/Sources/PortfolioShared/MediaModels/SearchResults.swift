/// What a search of a media server found, the best matches first.
public struct SearchResults: Hashable, Sendable {
    /// The items found: for Top Results or a genre, movies, shows, music videos and collections
    /// together; otherwise the filter's kind. None for people.
    public var items: [MediaItem]
    /// The episodes found besides, for Top Results.
    public var episodes: [MediaItem]
    /// The people found: for Top Results besides the items, or all there is for people.
    public var people: [Person]
    /// For Top Results, the kinds' filters that find anything for the same text: `.movies`, `.people`
    /// and so on.
    public var kinds: Set<SearchFilter>
    /// For Top Results, the genres of the items found, by name.
    public var genres: Set<String>

    public init(
        items: [MediaItem] = [],
        episodes: [MediaItem] = [],
        people: [Person] = [],
        kinds: Set<SearchFilter> = [],
        genres: Set<String> = []
    ) {
        self.items = items
        self.episodes = episodes
        self.people = people
        self.kinds = kinds
        self.genres = genres
    }

    /// Whether it found nothing at all.
    public var isEmpty: Bool {
        items.isEmpty && episodes.isEmpty && people.isEmpty
    }
}
