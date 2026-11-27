import PortfolioShared

/// Where focus is in Search, below the keyboard: on a filter, a poster, someone found, or the actions of
/// a card grown from a poster.
enum SearchFocus: Hashable {
    case filter(SearchFilter)
    case poster(MediaItem.ID)
    case person(Person.ID)
    case detail(MediaItem.ID)
}
