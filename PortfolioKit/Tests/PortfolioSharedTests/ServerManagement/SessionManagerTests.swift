import PortfolioSharedTestSupport
import Testing

@testable import PortfolioShared

@MainActor
struct SessionManagerTests {
    let storage = InMemorySecureStorage()
    let authority = FakeSessionAuthority()

    func makeManager() -> SessionManager {
        SessionManager(store: SessionStore(storage: storage), authority: authority)
    }

    func saved() throws -> UserSession? {
        try SessionStore(storage: storage).load()
    }

    @Test func startsRestoring() {
        #expect(makeManager().state == .restoring)
    }

    // MARK: Restore

    @Test func signsOutWhenNothingIsSaved() async {
        let manager = makeManager()
        await manager.restore()
        #expect(manager.state == .signedOut)
    }

    @Test func restoresASessionTheServerAccepts() async throws {
        try SessionStore(storage: storage).save(.sample(userName: "alex"))
        let renamed = User(id: "user-1", name: "Alex R.", serverID: "server-1", primaryImageTag: "new-avatar")
        authority.answer(.valid(renamed))

        let manager = makeManager()
        await manager.restore()

        // The server's current view of the user replaces the saved one, in memory and on disk.
        #expect(manager.state.session?.user == renamed)
        #expect(manager.state.session?.accessToken == "token-123")
        #expect(try saved()?.user == renamed)
    }

    @Test func keepsTheSessionWhenTheServerIsUnavailable() async throws {
        try SessionStore(storage: storage).save(.sample())
        authority.answer(.unavailable)

        let manager = makeManager()
        await manager.restore()

        #expect(manager.state == .signedIn(.sample()))
        #expect(try saved() == .sample())
    }

    @Test func signsOutAndForgetsARevokedSession() async throws {
        try SessionStore(storage: storage).save(.sample())
        authority.answer(.revoked)

        let manager = makeManager()
        await manager.restore()

        #expect(manager.state == .signedOut)
        #expect(try saved() == nil)
    }

    @Test func signsOutWhenStorageCannotBeRead() async {
        storage.failAllCalls(with: TestError("keychain unavailable"))

        let manager = makeManager()
        await manager.restore()

        #expect(manager.state == .signedOut)
    }

    // MARK: Sign-in and sign-out

    @Test func signingInSavesTheSession() throws {
        let manager = makeManager()

        try manager.signIn(.sample())

        #expect(manager.state == .signedIn(.sample()))
        #expect(try saved() == .sample())
    }

    @Test func aSessionThatCannotBeSavedDoesNotSignIn() {
        storage.failAllCalls(with: TestError("disk full"))
        let manager = makeManager()

        #expect(throws: TestError("disk full")) { try manager.signIn(.sample()) }
        #expect(manager.state == .restoring)
    }

    @Test func signingOutEndsTheSessionAndForgetsIt() async throws {
        let manager = makeManager()
        try manager.signIn(.sample())

        await manager.signOut()

        #expect(authority.endedSessions == [.sample()])
        #expect(manager.state == .signedOut)
        #expect(try saved() == nil)
    }

    @Test func signingOutWorksOffline() async throws {
        authority.failEndSession(with: TestError("offline"))
        let manager = makeManager()
        try manager.signIn(.sample())

        await manager.signOut()

        #expect(manager.state == .signedOut)
        #expect(try saved() == nil)
    }

    // MARK: Across launches

    @Test func aSessionSurvivesARelaunch() async throws {
        try makeManager().signIn(.sample())

        let afterRelaunch = makeManager()
        authority.answer(.valid(UserSession.sample().user))
        await afterRelaunch.restore()

        #expect(afterRelaunch.state == .signedIn(.sample()))
    }
}
