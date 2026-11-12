import Foundation
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioShared

struct MediaServerStoreTests {
    let storage = InMemorySecureStorage()
    var store: MediaServerStore { MediaServerStore(storage: storage) }

    let living = MediaServer(server: .sample(), users: [UserSession.sample().user], accessTokens: ["user-1": "token-123"])
    let office = MediaServer(server: .sample(id: "server-2", name: "Office"))

    @Test func loadsNothingWhenNothingIsSaved() throws {
        #expect(try store.load().isEmpty)
    }

    @Test func savesAndLoadsServersInOrder() throws {
        try store.save([living, office])
        #expect(try store.load() == [living, office])
    }

    @Test func keepsAccessTokens() throws {
        try store.save([living])
        #expect(try store.load().first?.session(for: "user-1") == .sample())
    }

    @Test func replacesWhatWasSaved() throws {
        try store.save([living, office])
        try store.save([office])
        #expect(try store.load() == [office])
        #expect(storage.contents.count == 1)
    }

    @Test(arguments: [
        Data("not json".utf8),
        Data(#"{"version": 2, "servers": []}"#.utf8),
    ])
    func discardsServersItCannotRead(_ data: Data) throws {
        storage.setRaw(data, forKey: MediaServerStore.key)

        #expect(try store.load().isEmpty)
        #expect(storage.contents.isEmpty)
    }

    @Test func savesAndLoadsTheProfileOpenedLast() throws {
        #expect(try store.loadLastOpenedProfile() == nil)

        try store.saveLastOpenedProfile(ProfileID(serverID: "server-2", userID: "sam"))

        #expect(try store.loadLastOpenedProfile() == ProfileID(serverID: "server-2", userID: "sam"))
    }

    @Test func ignoresALastOpenedProfileItCannotRead() throws {
        storage.setRaw(Data("not json".utf8), forKey: MediaServerStore.lastOpenedKey)
        #expect(try store.loadLastOpenedProfile() == nil)
    }

    @Test func removesEverythingSaved() throws {
        try store.save([living, office])
        try store.saveLastOpenedProfile(ProfileID(serverID: "server-1", userID: "user-1"))

        try store.removeAll()

        #expect(storage.contents.isEmpty)
        #expect(try store.load().isEmpty)
        #expect(try store.loadLastOpenedProfile() == nil)
    }

    @Test func passesStorageFailuresOn() {
        storage.failAllCalls(with: TestError("keychain locked"))
        #expect(throws: TestError("keychain locked")) { try store.load() }
        #expect(throws: TestError("keychain locked")) { try store.save([living]) }
    }
}
