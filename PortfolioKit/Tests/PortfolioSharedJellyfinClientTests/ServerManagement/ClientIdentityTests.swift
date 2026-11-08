import Foundation
import Testing

@testable import PortfolioSharedJellyfinClient

struct ClientIdentityTests {
    @Test func generatesTheDeviceIDOnceAndReusesIt() throws {
        let defaults = try #require(UserDefaults(suiteName: "ClientIdentityTests-\(UUID().uuidString)"))

        let first = ClientIdentity.persistentDeviceID(in: defaults)
        let second = ClientIdentity.persistentDeviceID(in: defaults)

        #expect(!first.isEmpty)
        #expect(first == second)
        #expect(defaults.string(forKey: ClientIdentity.deviceIDKey) == first)
    }

    @MainActor
    @Test func currentIdentityUsesThePersistedDeviceID() throws {
        let defaults = try #require(UserDefaults(suiteName: "ClientIdentityTests-\(UUID().uuidString)"))

        let identity = ClientIdentity.current(defaults: defaults)

        #expect(identity.deviceID == defaults.string(forKey: ClientIdentity.deviceIDKey))
        #expect(!identity.deviceName.isEmpty)
        #expect(!identity.clientName.isEmpty)
    }

    @Test(arguments: [
        ("Living, Room=\"TV\"", "Living RoomTV"),
        ("  Apple TV  ", "Apple TV"),
        (",,=", "Unknown"),
    ])
    func stripsCharactersThatBreakTheHeader(_ input: String, _ expected: String) {
        #expect(ClientIdentity.sanitized(input) == expected)
    }
}
