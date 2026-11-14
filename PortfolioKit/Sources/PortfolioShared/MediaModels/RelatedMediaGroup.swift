/// Media that belongs together, such as Continue Watching or a library's recently added items.
public struct RelatedMediaGroup: Hashable, Sendable, Identifiable {
    /// How the group's items are shown.
    public enum Style: Hashable, Sendable {
        /// Each in its own shape: a movie's poster, an episode's still.
        case posters
        /// Items someone is partway through, or up to next: each wide, with its landscape art and
        /// logo, and how far along it is.
        case inProgress
    }

    public let id: String
    public let title: String
    public let items: [MediaItem]
    public let style: Style

    public init(id: String, title: String, items: [MediaItem], style: Style = .posters) {
        self.id = id
        self.title = title
        self.items = items
        self.style = style
    }
}
