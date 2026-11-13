/// The items a library view shows: one of the server's libraries, or every library of a kind together,
/// such as all the movies across "Movies" and "4K Movies".
public enum LibraryScope: Hashable, Sendable {
    case library(Library)
    case kind(Library.Kind)

    /// The kind of items it holds.
    public var kind: Library.Kind {
        switch self {
        case .library(let library): library.kind
        case .kind(let kind): kind
        }
    }
}
