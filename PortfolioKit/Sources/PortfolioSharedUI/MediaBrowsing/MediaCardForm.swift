/// The forms a card takes, which follow from its `ViewState`. The same card changes form in place: its
/// frame grows or shrinks.
enum MediaCardForm: Hashable, Sendable {
    /// In its row.
    case poster
    /// Inset in the preview, running to the bottom of the screen.
    case platter
    /// Filling the screen.
    case fullScreen

    var showsDetails: Bool { self != .poster }
}
