import Foundation

/// Saves the current session, with its access token, in `SecureStorage`.
public struct SessionStore: Sendable {
    private let storage: any SecureStorage

    static let key = "session"

    public init(storage: any SecureStorage) {
        self.storage = storage
    }

    /// The saved session, or nil if there is none. A saved session that can no longer be read (for
    /// example, written in a format this version doesn't know) is discarded and also returns nil.
    public func load() throws -> UserSession? {
        guard let data = try storage.data(forKey: Self.key) else { return nil }
        guard let stored = try? JSONDecoder().decode(StoredSession.self, from: data),
            stored.version == StoredSession.currentVersion else {
            try storage.removeData(forKey: Self.key)
            return nil
        }
        return stored.session
    }

    public func save(_ session: UserSession) throws {
        let data = try JSONEncoder().encode(StoredSession(session: session))
        try storage.set(data, forKey: Self.key)
    }

    public func clear() throws {
        try storage.removeData(forKey: Self.key)
    }
}

/// The on-disk format. Versioned so a later format can migrate instead of failing to decode.
private struct StoredSession: Codable {
    static let currentVersion = 1

    var version = currentVersion
    var session: UserSession
}
