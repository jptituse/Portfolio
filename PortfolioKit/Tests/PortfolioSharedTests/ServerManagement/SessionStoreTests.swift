import Foundation
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioShared

struct SessionStoreTests {
    let storage = InMemorySecureStorage()
    var store: SessionStore { SessionStore(storage: storage) }

    @Test func loadsNothingWhenNothingIsSaved() throws {
        #expect(try store.load() == nil)
    }

    @Test func savesAndLoadsASession() throws {
        try store.save(.sample())
        #expect(try store.load() == .sample())
    }

    @Test func replacesTheSavedSession() throws {
        try store.save(.sample(userName: "alex"))
        try store.save(.sample(userName: "sam"))
        #expect(try store.load()?.user.name == "sam")
        #expect(storage.contents.count == 1)
    }

    @Test func clearsTheSavedSession() throws {
        try store.save(.sample())
        try store.clear()
        #expect(try store.load() == nil)
        #expect(storage.contents.isEmpty)
    }

    @Test(arguments: [
        Data("not json".utf8),
        Data(#"{"version": 2, "session": {}}"#.utf8),
    ])
    func discardsSessionsItCannotRead(_ data: Data) throws {
        storage.setRaw(data, forKey: SessionStore.key)

        #expect(try store.load() == nil)
        #expect(storage.contents.isEmpty)
    }

    @Test func passesStorageFailuresOn() {
        storage.failAllCalls(with: TestError("keychain locked"))
        #expect(throws: TestError("keychain locked")) { try store.load() }
        #expect(throws: TestError("keychain locked")) { try store.save(.sample()) }
    }
}
