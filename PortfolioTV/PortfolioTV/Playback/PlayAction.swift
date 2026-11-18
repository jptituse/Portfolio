import PortfolioShared

/// Plays an item from a position, full screen. `showDetails`, if given, shows the item's detail view
/// behind the player as it closes, so Back from playing lands there: for a player that didn't open from
/// the detail view itself, such as the banner's Play, or Continue Watching playing what's selected.
typealias PlayAction = (_ item: MediaItem, _ position: Duration, _ showDetails: (() -> Void)?) -> Void
