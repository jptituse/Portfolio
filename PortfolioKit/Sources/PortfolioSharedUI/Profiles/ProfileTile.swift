import Foundation

/// What a person's tile in a picker shows: their picture, or their initials when there isn't one,
/// their name, and a line under it.
public struct ProfileTile: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// Under the name, such as the server they're on.
    public let detail: String?
    public let pictureURL: URL?
    /// Shown in place of a picture.
    public let initials: String

    init(id: String, name: String, detail: String? = nil, pictureURL: URL?) {
        self.id = id
        self.name = name
        self.detail = detail
        self.pictureURL = pictureURL
        self.initials = Self.initials(of: name)
    }

    /// The first letters of the first two words: "Alex Rivera" is "AR", and "alex" is "A".
    static func initials(of name: String) -> String {
        name.split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap(\.first)
            .map { $0.uppercased() }
            .joined()
    }
}
