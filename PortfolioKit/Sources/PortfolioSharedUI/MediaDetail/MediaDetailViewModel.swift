import Observation
import PortfolioShared

/// What `MediaDetailView` shows for an item, and the detail views it leads to.
@MainActor
@Observable
public final class MediaDetailViewModel {
    private let item: MediaItem
    /// How far down the detail views this one is: the first one an item opens is 1.
    // FIXME: Replace `depth` and `deeper()` with the item's seasons, cast and related items (#13).
    private let depth: Int

    public convenience init(item: MediaItem) {
        self.init(item: item, depth: 1)
    }

    private init(item: MediaItem, depth: Int) {
        self.item = item
        self.depth = depth
    }

    var title: String { item.name }
    var heading: String { "Detail view \(depth)" }

    /// The detail view "Go deeper" leads to: the same item, one level down.
    func deeper() -> MediaDetailViewModel {
        MediaDetailViewModel(item: item, depth: depth + 1)
    }
}
