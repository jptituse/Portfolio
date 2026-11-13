/// Part of a long list of items, from `startIndex`, and how many there are in all.
public struct MediaItemPage: Hashable, Sendable {
    public let items: [MediaItem]
    public let startIndex: Int
    public let totalCount: Int

    public init(items: [MediaItem], startIndex: Int, totalCount: Int) {
        self.items = items
        self.startIndex = startIndex
        self.totalCount = totalCount
    }
}
