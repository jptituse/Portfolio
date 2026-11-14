/// The server's reference to one of an item's images, and whose image it is: the item's own, or one it
/// borrows, such as an episode showing its show's backdrop and logo.
///
/// Opaque to the UI: the server integration that produced the item resolves it into a URL
/// (`MediaImageResolver`). It changes whenever its image does, so it doubles as a cache key. A string
/// literal is a reference to the item's own image with that tag.
public struct MediaImageReference: Hashable, Sendable, ExpressibleByStringLiteral {
    public let tag: String
    /// The item the image belongs to, or nil for the item itself.
    public let ownerID: String?

    public init(tag: String, ownerID: String? = nil) {
        self.tag = tag
        self.ownerID = ownerID
    }

    public init(stringLiteral tag: String) {
        self.init(tag: tag)
    }
}
