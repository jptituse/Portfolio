/// An entry in a library's own sidebar: which of its items the grid beside it lists, and in what order.
public enum LibrarySidebarItem: Hashable, Sendable {
    /// Newest first: for shows, the ones with the newest episodes.
    case recentlyAdded
    /// Everything, by name.
    case all
    /// The items in a genre, by name.
    case genre(Genre)
}
