/// Media that belongs together, such as Continue Watching or a library's recently added items.
public struct RelatedMediaGroup: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let items: [MediaItem]

    public init(id: String, title: String, items: [MediaItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}
