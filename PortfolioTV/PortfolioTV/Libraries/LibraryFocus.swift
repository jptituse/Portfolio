import PortfolioShared

/// Where focus is in a library view: on one of its sidebar items, on a poster in its grid, or on the
/// actions of a card expanded from one.
enum LibraryFocus: Hashable {
    case sidebarItem(LibrarySidebarItem)
    case poster(MediaItem.ID)
    case detail(MediaItem.ID)
}
