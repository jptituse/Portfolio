import Foundation
import Security

/// Stores small secrets, such as a session with its access token, by key.
public protocol SecureStorage: Sendable {
    func data(forKey key: String) throws -> Data?
    func set(_ data: Data, forKey key: String) throws
    func removeData(forKey key: String) throws
}

/// `SecureStorage` backed by the Keychain, as generic password items.
public struct KeychainStorage: SecureStorage {
    /// Groups this app's items in the Keychain.
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public func data(forKey key: String) throws -> Data? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    public func set(_ data: Data, forKey key: String) throws {
        let query = baseQuery(forKey: key)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = query
            item[kSecValueData as String] = data
            // Readable once the device has been unlocked after boot, so a relaunch in the background
            // (or a Top Shelf extension later) can restore the session.
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        default:
            throw KeychainError(status: updateStatus)
        }
    }

    public func removeData(forKey key: String) throws {
        let status = SecItemDelete(baseQuery(forKey: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    private func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}

/// A Keychain call failed with this `OSStatus`.
public struct KeychainError: Error, Hashable, Sendable, CustomStringConvertible {
    public let status: OSStatus

    public var description: String {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
        return "Keychain error \(status): \(message)"
    }
}
