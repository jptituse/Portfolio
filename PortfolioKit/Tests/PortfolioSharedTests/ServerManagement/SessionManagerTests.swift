import PortfolioSharedTestSupport
import Testing

@testable import PortfolioShared

@MainActor
struct SessionManagerTests {
    let storage = InMemorySecureStorage()
    let authority = FakeSessionAuthority()

    func makeManager() -> SessionManager {
        SessionManager(store: MediaServerStore(storage: storage), authority: authority)
    }

    /// A manager that has just launched with `session` saved.
    func launch(with session: UserSession) throws -> SessionManager {
        try makeManager().signIn(session)
        let manager = makeManager()
        manager.restore()
        return manager
    }

    func saved() throws -> [MediaServer] {
        try MediaServerStore(storage: storage).load()
    }

    @Test func startsRestoring() {
        #expect(makeManager().state == .restoring)
    }

    // MARK: Launch

    @Test func launchesSignedOutWithNothingSaved() {
        let manager = makeManager()
        manager.restore()
        #expect(manager.state == .choosingProfile)
        #expect(manager.servers.isEmpty)
    }

    @Test func launchesSignedOutWithTheMediaServers() throws {
        let manager = try launch(with: .sample())

        // Someone has to pick their profile first.
        #expect(manager.state == .choosingProfile)
        #expect(manager.servers.map(\.server) == [.sample()])
        #expect(manager.servers.first?.isSignedIn("user-1") == true)
    }

    @Test func launchesWithNothingWhenStorageCannotBeRead() {
        storage.failAllCalls(with: TestError("keychain unavailable"))

        let manager = makeManager()
        manager.restore()

        #expect(manager.state == .choosingProfile)
        #expect(manager.servers.isEmpty)
    }

    // MARK: Opening a profile

    @Test func opensAProfileTheServerStillAccepts() async throws {
        let manager = try launch(with: .sample(userName: "alex"))
        let renamed = User(id: "user-1", name: "Alex R.", serverID: "server-1", primaryImageTag: "new-avatar")
        authority.answer(.valid(renamed))

        #expect(await manager.open("user-1", on: "server-1"))

        // The server's current view of the user replaces the saved one, in memory and on disk.
        #expect(manager.state.session?.user == renamed)
        #expect(manager.state.session?.accessToken == "token-123")
        #expect(try saved().first?.users == [renamed])
    }

    @Test func opensAProfileWhileTheServerIsUnavailable() async throws {
        let manager = try launch(with: .sample())
        authority.answer(.unavailable)

        #expect(await manager.open("user-1", on: "server-1"))
        #expect(manager.state == .signedIn(.sample()))
    }

    @Test func forgetsASessionTheServerRevoked() async throws {
        let manager = try launch(with: .sample())
        authority.answer(.revoked)

        #expect(await manager.open("user-1", on: "server-1") == false)

        #expect(manager.state == .choosingProfile)
        #expect(try saved().first?.isSignedIn("user-1") == false)
        // They're still on the profile picker, to sign in again.
        #expect(try saved().first?.users.map(\.id) == ["user-1"])
    }

    @Test func cannotOpenAProfileThatIsSignedOut() async throws {
        let manager = try launch(with: .sample())
        manager.updateListedUsers([User(id: "sam", name: "Sam", serverID: "server-1", primaryImageTag: nil)], on: "server-1")

        #expect(await manager.open("sam", on: "server-1") == false)
        #expect(manager.state == .choosingProfile)
    }

    // MARK: Signing in

    @Test func signingInToANewServerAddsAndSavesIt() throws {
        let manager = makeManager()

        try manager.signIn(.sample())

        #expect(manager.state == .signedIn(.sample()))
        #expect(try saved() == manager.servers)
        #expect(manager.servers.first?.session(for: "user-1") == .sample())
    }

    @Test func signingInToAMediaServerAddsTheUserAndKeepsTheOthers() throws {
        let manager = try launch(with: .sample(userID: "alex", userName: "Alex"))
        let movedServer = ServerInfo.sample(url: "https://media.example.com")

        try manager.signIn(.sample(userID: "sam", userName: "Sam", token: "sam-token", server: movedServer))

        #expect(manager.servers.count == 1)
        #expect(manager.servers[0].server.url == movedServer.url)
        #expect(manager.servers[0].users.map(\.name) == ["Alex", "Sam"])
        #expect(manager.servers[0].isSignedIn("alex"))
        #expect(manager.servers[0].isSignedIn("sam"))
    }

    @Test func aSessionThatCannotBeSavedChangesNothing() {
        storage.failAllCalls(with: TestError("disk full"))
        let manager = makeManager()

        #expect(throws: TestError("disk full")) { try manager.signIn(.sample()) }
        #expect(manager.state == .restoring)
        #expect(manager.servers.isEmpty)
    }

    @Test func takesTheUsersAServerListsNow() throws {
        let manager = try launch(with: .sample(userID: "alex", userName: "Alex"))
        let sam = User(id: "sam", name: "Sam", serverID: "server-1", primaryImageTag: nil)

        manager.updateListedUsers([sam], on: "server-1")

        #expect(manager.servers[0].users.map(\.name) == ["Sam", "Alex"])
        #expect(try saved()[0].users.map(\.name) == ["Sam", "Alex"])
    }

    // MARK: The profile opened last

    @Test func remembersTheProfileOpenedLastAcrossLaunches() async throws {
        let manager = try launch(with: .sample(userID: "alex", userName: "Alex"))
        try manager.signIn(.sample(userID: "sam", userName: "Sam", token: "sam-token"))
        manager.closeProfile()
        authority.answer(.unavailable)
        #expect(await manager.open("alex", on: "server-1"))

        let relaunched = makeManager()
        relaunched.restore()

        #expect(relaunched.lastOpenedProfile == ProfileID(serverID: "server-1", userID: "alex"))
    }

    @Test func aProfileThatDoesNotOpenIsNotRemembered() async throws {
        let manager = try launch(with: .sample(userID: "alex", userName: "Alex"))
        manager.updateListedUsers([User(id: "sam", name: "Sam", serverID: "server-1", primaryImageTag: nil)], on: "server-1")

        #expect(await manager.open("sam", on: "server-1") == false)

        #expect(manager.lastOpenedProfile == ProfileID(serverID: "server-1", userID: "alex"))
    }

    // MARK: Switching profiles

    @Test func closingAProfileKeepsItSignedInToOpenAgain() async throws {
        let manager = makeManager()
        try manager.signIn(.sample())

        manager.closeProfile()

        #expect(manager.state == .choosingProfile)
        #expect(authority.endedSessions.isEmpty)
        #expect(try saved().first?.isSignedIn("user-1") == true)
        authority.answer(.unavailable)
        #expect(await manager.open("user-1", on: "server-1"))
    }

    @Test func closingWithNoProfileOpenDoesNothing() {
        let manager = makeManager()

        manager.closeProfile()

        #expect(manager.state == .restoring)
    }

    // MARK: Signing out

    @Test func signingOutEndsTheSessionAndKeepsTheProfile() async throws {
        let manager = makeManager()
        try manager.signIn(.sample())

        await manager.signOut()

        #expect(authority.endedSessions == [.sample()])
        #expect(manager.state == .choosingProfile)
        #expect(try saved().first?.isSignedIn("user-1") == false)
        #expect(try saved().first?.users.map(\.id) == ["user-1"])
    }

    @Test func signingOutWorksOffline() async throws {
        authority.failEndSession(with: TestError("offline"))
        let manager = makeManager()
        try manager.signIn(.sample())

        await manager.signOut()

        #expect(manager.state == .choosingProfile)
        #expect(try saved().first?.isSignedIn("user-1") == false)
    }

    // MARK: Removing all servers

    @Test func removingAllServersStartsOverAndEndsEachSession() async throws {
        let alex = UserSession.sample(userID: "alex", userName: "Alex")
        let sam = UserSession.sample(userID: "sam", userName: "Sam", token: "sam-token", server: .sample(id: "server-2", name: "Office"))
        let manager = try launch(with: alex)
        manager.updateListedUsers([User(id: "kim", name: "Kim", serverID: "server-1", primaryImageTag: nil)], on: "server-1")
        try manager.signIn(sam)

        try await manager.removeAllServers()

        #expect(manager.state == .choosingProfile)
        #expect(manager.servers.isEmpty)
        #expect(manager.lastOpenedProfile == nil)
        // Only signed-in profiles have a session to end.
        #expect(authority.endedSessions == [alex, sam])
        // Nothing comes back at the next launch.
        let relaunched = makeManager()
        relaunched.restore()
        #expect(relaunched.servers.isEmpty)
        #expect(relaunched.lastOpenedProfile == nil)
    }

    @Test func removingAllServersWorksOffline() async throws {
        authority.failEndSession(with: TestError("offline"))
        let manager = try launch(with: .sample())

        try await manager.removeAllServers()

        #expect(manager.servers.isEmpty)
        #expect(try saved().isEmpty)
    }

    @Test func serversThatCannotBeRemovedStay() async throws {
        let manager = try launch(with: .sample())
        storage.failAllCalls(with: TestError("keychain locked"))

        await #expect(throws: TestError("keychain locked")) { try await manager.removeAllServers() }

        #expect(manager.servers.map(\.server) == [.sample()])
        #expect(authority.endedSessions.isEmpty)
    }

    // MARK: Opening the last profile at launch

    @Test func opensTheProfileOpenedLastAtLaunch() async throws {
        let manager = try launch(with: .sample())
        let relaunched = makeManager()

        await relaunched.restoreOpeningLastProfile()

        #expect(relaunched.state == .signedIn(.sample()))
        _ = manager
    }

    @Test func launchesOnTheProfilePickerIfTheLastProfileWasSignedOut() async throws {
        let manager = try launch(with: .sample())
        try manager.signIn(.sample())
        await manager.signOut()
        let relaunched = makeManager()

        await relaunched.restoreOpeningLastProfile()

        #expect(relaunched.state == .choosingProfile)
    }

    @Test func launchesOnTheProfilePickerIfTheServerRevokedTheLastProfile() async throws {
        _ = try launch(with: .sample())
        authority.answer(.revoked)
        let relaunched = makeManager()

        await relaunched.restoreOpeningLastProfile()

        #expect(relaunched.state == .choosingProfile)
    }

    // MARK: Adding an account from Settings

    @Test func addingAnAccountSavesItWithoutOpeningIt() throws {
        let alex = UserSession.sample(userID: "alex", userName: "Alex")
        let sam = UserSession.sample(userID: "sam", userName: "Sam", token: "sam-token", server: .sample(id: "server-2", name: "Office"))
        let manager = makeManager()
        try manager.signIn(alex)

        try manager.add(sam)

        #expect(manager.state == .signedIn(alex))
        #expect(manager.lastOpenedProfile == ProfileID(serverID: "server-1", userID: "alex"))
        #expect(try saved().map(\.id) == ["server-1", "server-2"])
        #expect(manager.servers[1].session(for: "sam") == sam)
    }

    // MARK: Signing an account out

    @Test func signingOutAnotherAccountKeepsTheOpenProfileOpen() async throws {
        let alex = UserSession.sample(userID: "alex", userName: "Alex")
        let sam = UserSession.sample(userID: "sam", userName: "Sam", token: "sam-token")
        let manager = makeManager()
        try manager.add(sam)
        try manager.signIn(alex)

        await manager.signOut("sam", on: "server-1")

        #expect(manager.state == .signedIn(alex))
        #expect(try saved().first?.isSignedIn("sam") == false)
        #expect(try saved().first?.isSignedIn("alex") == true)
        #expect(authority.endedSessions == [sam])
        // Still on the profile picker.
        #expect(manager.servers.first?.users.map(\.id) == ["sam", "alex"])
    }

    @Test func signingOutTheOpenProfileClosesIt() async throws {
        let manager = makeManager()
        try manager.signIn(.sample())

        await manager.signOut("user-1", on: "server-1")

        #expect(manager.state == .choosingProfile)
        #expect(try saved().first?.isSignedIn("user-1") == false)
    }

    // MARK: Removing a server

    @Test func removingAServerForgetsItsProfilesAndEndsTheirSessions() async throws {
        let alex = UserSession.sample(userID: "alex", userName: "Alex")
        let sam = UserSession.sample(userID: "sam", userName: "Sam", token: "sam-token", server: .sample(id: "server-2", name: "Office"))
        let manager = makeManager()
        try manager.add(sam)
        try manager.signIn(alex)

        try await manager.removeServer("server-2")

        #expect(manager.state == .signedIn(alex))
        #expect(manager.servers.map(\.id) == ["server-1"])
        #expect(try saved().map(\.id) == ["server-1"])
        #expect(authority.endedSessions == [sam])
    }

    @Test func removingTheOpenProfilesServerClosesItAndForgetsItWasOpenedLast() async throws {
        let sam = UserSession.sample(userID: "sam", userName: "Sam", token: "sam-token", server: .sample(id: "server-2", name: "Office"))
        let manager = makeManager()
        try manager.add(.sample())
        try manager.signIn(sam)

        try await manager.removeServer("server-2")

        #expect(manager.state == .choosingProfile)
        #expect(manager.lastOpenedProfile == nil)
        let relaunched = makeManager()
        relaunched.restore()
        #expect(relaunched.lastOpenedProfile == nil)
        #expect(relaunched.servers.map(\.id) == ["server-1"])
    }

    @Test func removingTheLastServerStartsOver() async throws {
        let manager = try launch(with: .sample())

        try await manager.removeServer("server-1")

        #expect(manager.servers.isEmpty)
        #expect(try saved().isEmpty)
    }

    // MARK: Changing a server's address

    @Test func aServerAtANewAddressKeepsItsAccountsSignedIn() throws {
        let manager = makeManager()
        try manager.signIn(.sample())
        let moved = ServerInfo.sample(url: "http://192.168.1.20:8920")

        try manager.updateAddress(of: moved)

        #expect(manager.servers.first?.server.url == moved.url)
        #expect(try saved().first?.server.url == moved.url)
        #expect(try saved().first?.isSignedIn("user-1") == true)
        // The open profile reaches it there from now on.
        #expect(manager.state.session?.server.url == moved.url)
    }

    // MARK: Someone renamed

    @Test func takesARenamedUserHereAndInTheOpenProfile() throws {
        let manager = makeManager()
        try manager.signIn(.sample())
        let renamed = User(id: "user-1", name: "Alex Rivera", serverID: "server-1", primaryImageTag: "new-picture")

        manager.updateUser(renamed, on: "server-1")

        #expect(manager.servers.first?.users == [renamed])
        #expect(try saved().first?.users == [renamed])
        #expect(manager.state.session?.user == renamed)
        #expect(manager.state.session?.accessToken == "token-123")
    }
}
