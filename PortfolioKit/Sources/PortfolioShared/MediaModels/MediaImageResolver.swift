import Foundation

/// Turns an item's image references (`MediaItem.images`) into URLs, sized for where each image is
/// drawn. The server integration that produced the item provides one.
public protocol MediaImageResolver: Sendable {
    /// Where `item`'s `kind` image is, or nil if the item doesn't have one.
    ///
    /// - Parameter pixelSize: the size it's drawn at, in pixels. Logos come back fitting inside it;
    ///   anything else comes back covering it, keeping its proportions. Neither is ever enlarged.
    func url(for item: MediaItem, _ kind: MediaImageKind, pixelSize: CGSize) -> URL?
}
