import Foundation
import PortfolioShared
import Synchronization

/// The in-memory stand-in for the Keychain in tests.
public final class InMemorySecureStorage: SecureStorage {
    private let items = Mutex<[String: Data]>([:])
    private let failure = Mutex<(any Error)?>(nil)

    public init() {}

    /// Everything stored, by key.
    public var contents: [String: Data] { items.withLock { $0 } }

    /// Makes every later call throw `error` (or succeed again with nil), like a Keychain that fails.
    public func failAllCalls(with error: (any Error)?) {
        failure.withLock { $0 = error }
    }

    public func data(forKey key: String) throws -> Data? {
        try throwIfFailing()
        return items.withLock { $0[key] }
    }

    public func set(_ data: Data, forKey key: String) throws {
        try throwIfFailing()
        items.withLock { $0[key] = data }
    }

    public func removeData(forKey key: String) throws {
        try throwIfFailing()
        items.withLock { _ = $0.removeValue(forKey: key) }
    }

    /// Stores raw bytes, for testing what happens with data the app didn't write.
    public func setRaw(_ data: Data, forKey key: String) {
        items.withLock { $0[key] = data }
    }

    private func throwIfFailing() throws {
        if let error = failure.withLock({ $0 }) { throw error }
    }
}
