import PortfolioShared

/// Where focus is on Home, outside its rows: on the banner's buttons, or on the actions of the detail
/// card its Info button opens.
enum HomeFocus: Hashable {
    case bannerInfo
    case bannerNext
    /// Just left of the banner's buttons, where focus goes on Left while there's a banner before the
    /// one showing. Nothing's drawn there: landing on it goes back a banner, and focus returns.
    case bannerLeftEdge
    /// The same just right of them, while there's a banner after the one showing.
    case bannerRightEdge
    case detail(MediaItem.ID)
}
