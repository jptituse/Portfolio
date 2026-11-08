import Observation
import PortfolioShared

/// What a `MediaCardView` shows: its content and the state it's in. The card watches this, so the same
/// card stays on screen while its content and state change.
@MainActor
@Observable
public final class MediaCardViewModel {
    public var item: MediaItem {
        didSet { detailInfo.update(with: item) }
    }
    /// The card's own layer while its hierarchy is in `.preview`. Setting a previewed card to `.root`
    /// expands it to fill the screen.
    public var viewState: ViewState = .preview
    /// Whether this is the highlighted card. In a preview, the cards that aren't are darkened.
    public var isFocused = false
    /// Whether a poster has widened to show its landscape thumbnail.
    public var isExtended = false
    /// Whether the labels of the card's current form are showing.
    public var showsLabels = true

    let detailInfo: MediaDetailInfoViewModel

    public init(item: MediaItem) {
        self.item = item
        detailInfo = MediaDetailInfoViewModel(item: item)
    }

    /// The title shown on the poster.
    var title: String { item.name }

    /// A hue for the stand-in artwork, the same for an item on every launch.
    // FIXME: Remove this once cards show the item's artwork from the server (#9).
    var artworkHue: Double {
        // A stable hash: `hashValue` changes between launches.
        let hash = item.id.unicodeScalars.reduce(0) { ($0 * Self.hashMultiplier + Int($1.value)) % Self.hueSteps }
        return Double(hash) / Double(Self.hueSteps)
    }

    /// The card's form in a hierarchy at `layer`.
    func form(in layer: ViewState) -> MediaCardForm {
        switch (layer, viewState) {
        case (.root, _): .poster
        case (.preview, .preview): .platter
        case (.preview, .root): .fullScreen
        }
    }

    /// Whether the poster title shows: only on a poster, and only while the labels are showing.
    func showsTitle(in layer: ViewState) -> Bool {
        !form(in: layer).showsDetails && showsLabels
    }

    /// Whether the details show: only once the card is bigger than a poster, and only while the labels
    /// are showing.
    func showsDetails(in layer: ViewState) -> Bool {
        form(in: layer).showsDetails && showsLabels
    }

    /// Whether the card is darkened: in a preview, the platters that aren't highlighted are.
    func isDimmed(in layer: ViewState) -> Bool {
        form(in: layer) == .platter && !isFocused
    }

    private static let hashMultiplier = 31
    private static let hueSteps = 360
}
