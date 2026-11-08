import Foundation
import Testing

@testable import PortfolioSharedJellyfinClient

/// Real server responses, for testing how SDK types map to `PortfolioShared` models.
enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        try JSONDecoder().decode(type, from: data(name))
    }
}

extension ClientIdentity {
    static let test = ClientIdentity(clientName: "Portfolio", version: "1.0", deviceName: "Apple TV", deviceID: "device-123")
}

extension JellyfinServerClient {
    /// A client whose requests go to `MockJellyfinServer` instances.
    static let mocked = JellyfinServerClient(identity: .test, sessionConfiguration: { MockJellyfinServer.sessionConfiguration })
}
