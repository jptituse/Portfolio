import SwiftUI

/// The layer a view is in. It's inherited down the view hierarchy, so setting it on a view tells
/// everything beneath that view that it has entered a different layer.
///
/// Changing it inside an animation moves views to their place in the new layer, so it also works as a
/// transition style. A card in a row, for example, is a poster while the view holding the row is at
/// `.root`. When that view enters `.preview` the card grows into a platter, and setting that previewed
/// card to `.root` expands it to fill the screen. A card set to `.root` while it's still a poster goes
/// straight to full screen when its view enters `.preview`, skipping the platter.
public enum ViewState: Hashable, Sendable {
    /// The main layer of a view.
    case root
    /// A layer previewing content above the main one.
    case preview
}

extension EnvironmentValues {
    /// The layer this part of the view hierarchy is in.
    @Entry public var viewState: ViewState = .root
}
