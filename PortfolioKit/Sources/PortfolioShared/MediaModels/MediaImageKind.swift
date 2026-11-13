/// A kind of image an item can have, and the key to its reference in `MediaItem.images`.
public enum MediaImageKind: Hashable, Sendable {
    /// The item's main image: a movie's poster, an episode's still.
    case primary
    /// A landscape image made for wide cards, often with the title on it.
    case thumb
    /// The title as artwork with a transparent background.
    case logo
    /// Art to fill the screen behind the item. An item can have several.
    case backdrop(index: Int = 0)
}
