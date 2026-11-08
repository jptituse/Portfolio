import PortfolioShared

/// What holds focus in a browsing view.
enum BrowsingFocus: Hashable {
    /// A poster in a row. The same item can be in more than one group.
    case poster(MediaItem.ID, group: RelatedMediaGroup.ID)
    case platter(MediaItem.ID)
    /// The full-screen card's actions.
    case detail(MediaItem.ID)
}
