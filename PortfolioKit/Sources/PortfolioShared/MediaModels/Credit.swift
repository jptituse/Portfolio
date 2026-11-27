/// Someone credited on an item, and their part in it: an actor and the character they play, or its
/// director.
public struct Credit: Hashable, Sendable, Identifiable {
    /// A credited part.
    public enum Kind: Hashable, Sendable {
        case actor
        case guestStar
        case director
        case writer
        case producer
        case composer
        case creator
        case other(String)
    }

    /// The person's identifier on their server.
    public let personID: String
    public let name: String
    public let kind: Kind
    /// The character an actor plays, or a crew member's job as the server names it, if known.
    public let role: String?
    /// The tag of the person's picture, opaque like `MediaItem.images`, or nil without one.
    public let imageTag: String?

    public var id: String { "\(personID)/\(kind)/\(role ?? "")" }

    public init(personID: String, name: String, kind: Kind, role: String? = nil, imageTag: String? = nil) {
        self.personID = personID
        self.name = name
        self.kind = kind
        self.role = role
        self.imageTag = imageTag
    }
}
