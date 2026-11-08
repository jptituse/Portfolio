/// A Jellyfin server version (`major.minor.patch`), as reported by `/System/Info/Public`.
///
/// Jellyfin-specific: the shared `ServerInfo` model only carries the version as display text.
public struct ServerVersion: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    /// The oldest server the app supports. 10.10 introduced the MediaSegments API that
    /// intro/recap/outro skipping relies on.
    public static let minimumSupported = ServerVersion(major: 10, minor: 10, patch: 0)

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses strings such as `"10.10.7"`, `"10.11"` or `"10.11.0-rc1"`. Anything after the third
    /// numeric component is ignored.
    public init?(_ string: String) {
        let components = string.split(separator: ".", omittingEmptySubsequences: false).prefix(3)
        let numbers = components.map { Int($0.prefix(while: \.isNumber)) }
        guard numbers.count >= 2, let major = numbers[0], let minor = numbers[1] else { return nil }
        let patch = numbers.count > 2 ? (numbers[2] ?? 0) : 0
        self.init(major: major, minor: minor, patch: patch)
    }

    public var isSupported: Bool { self >= .minimumSupported }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: ServerVersion, rhs: ServerVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
