/// Someone on a media server: anyone credited on its items, such as an actor or a director.
public struct Person: Hashable, Sendable, Identifiable {
    /// Their identifier on their server.
    public let id: String
    public let name: String
    /// The tag of their picture, opaque like `MediaItem.images`, or nil without one.
    public let imageTag: String?

    public init(id: String, name: String, imageTag: String? = nil) {
        self.id = id
        self.name = name
        self.imageTag = imageTag
    }
}
