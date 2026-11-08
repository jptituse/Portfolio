import Foundation

#if canImport(UIKit)
    import UIKit
#endif

/// Who this app is, as the server sees it. Sent in the `Authorization: MediaBrowser …` header on
/// every request and shown in the server dashboard's device list.
public struct ClientIdentity: Hashable, Sendable {
    public let clientName: String
    public let version: String
    public let deviceName: String
    /// Stable per installation, so the server keeps one device entry instead of a new one per launch.
    public let deviceID: String

    public init(clientName: String, version: String, deviceName: String, deviceID: String) {
        self.clientName = Self.sanitized(clientName)
        self.version = Self.sanitized(version)
        self.deviceName = Self.sanitized(deviceName)
        self.deviceID = Self.sanitized(deviceID)
    }

    /// The identity of the running app: its bundle name and version, the device name, and a device
    /// ID generated on first use and reused after that.
    @MainActor
    public static func current(bundle: Bundle = .main, defaults: UserDefaults = .standard) -> ClientIdentity {
        let name =
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Portfolio"
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
        #if canImport(UIKit)
            let deviceName = UIDevice.current.name
        #else
            let deviceName = Host.current().localizedName ?? "Mac"
        #endif
        return ClientIdentity(
            clientName: name,
            version: version,
            deviceName: deviceName,
            deviceID: persistentDeviceID(in: defaults)
        )
    }

    static let deviceIDKey = "jellyfin.deviceID"

    /// Returns the stored device ID, generating and storing one on first use.
    static func persistentDeviceID(in defaults: UserDefaults) -> String {
        if let existing = defaults.string(forKey: deviceIDKey), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString
        defaults.set(generated, forKey: deviceIDKey)
        return generated
    }

    /// The SDK writes header fields unquoted (`Device=Apple TV, Client=…`), so a comma, quote or `=`
    /// in a value would corrupt the header. Those characters are dropped.
    static func sanitized(_ value: String) -> String {
        let cleaned = value.unicodeScalars.filter { !",=\"".unicodeScalars.contains($0) }
        let result = String(String.UnicodeScalarView(cleaned)).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "Unknown" : result
    }
}
