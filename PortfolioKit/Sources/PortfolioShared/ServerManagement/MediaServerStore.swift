import Foundation

/// Saves the servers added on this device, with their users and access tokens, and which profile was
/// opened last, in `SecureStorage`.
public struct MediaServerStore: Sendable {
    private let storage: any SecureStorage

    static let key = "servers"
    static let lastOpenedKey = "lastOpenedProfile"

    public init(storage: any SecureStorage) {
        self.storage = storage
    }

    /// The saved servers, in the order they were added. Servers saved in a format this version can't
    /// read are discarded, which leaves none.
    public func load() throws -> [MediaServer] {
        guard let data = try storage.data(forKey: Self.key) else { return [] }
        guard let stored = try? JSONDecoder().decode(StoredServers.self, from: data),
            stored.version == StoredServers.currentVersion else {
            try storage.removeData(forKey: Self.key)
            return []
        }
        return stored.servers
    }

    public func save(_ servers: [MediaServer]) throws {
        let data = try JSONEncoder().encode(StoredServers(servers: servers))
        try storage.set(data, forKey: Self.key)
    }

    /// The profile opened last, or nil if none has been, or it can't be read.
    public func loadLastOpenedProfile() throws -> ProfileID? {
        guard let data = try storage.data(forKey: Self.lastOpenedKey) else { return nil }
        return try? JSONDecoder().decode(ProfileID.self, from: data)
    }

    public func saveLastOpenedProfile(_ profile: ProfileID) throws {
        try storage.set(try JSONEncoder().encode(profile), forKey: Self.lastOpenedKey)
    }

    /// Removes everything saved. The servers go last, so if removing fails partway, they're still
    /// there to try again.
    public func removeAll() throws {
        try storage.removeData(forKey: Self.lastOpenedKey)
        try storage.removeData(forKey: Self.key)
    }
}

/// The on-disk format. Versioned so a later format can migrate instead of failing to decode.
private struct StoredServers: Codable {
    static let currentVersion = 1

    var version = currentVersion
    var servers: [MediaServer]
}
