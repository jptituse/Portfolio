import PortfolioShared
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedJellyfinClient

/// The whole session lifecycle: `SessionManager` with an in-memory Keychain, talking to a mock
/// Jellyfin server through the real client. A new `SessionManager` on the same storage stands in for
/// relaunching the app.
@MainActor
struct SessionLifecycleTests {
    let mock = MockJellyfinServer(accounts: [.init(name: "alex", password: "hunter2")])
    let keychain = InMemorySecureStorage()
    let client = JellyfinServerClient.mocked

    func launchApp() -> SessionManager {
        let manager = SessionManager(store: MediaServerStore(storage: keychain), authority: client)
        manager.restore()
        return manager
    }

    func signIn(with manager: SessionManager) async throws -> UserSession {
        let server = try await client.validateServer(at: mock.url)
        let session = try await client.signIn(to: server, username: "alex", password: "hunter2")
        try manager.signIn(session)
        return session
    }

    @Test func aFreshInstallStartsWithNoServers() {
        let manager = launchApp()
        #expect(manager.state == .choosingProfile)
        #expect(manager.servers.isEmpty)
    }

    @Test func aSignedInProfileOpensAfterARelaunch() async throws {
        let session = try await signIn(with: launchApp())

        let relaunched = launchApp()
        #expect(relaunched.state == .choosingProfile)
        #expect(await relaunched.open(session.user.id, on: session.server.id))

        #expect(relaunched.state.session?.user.name == "alex")
        #expect(relaunched.state.session?.server.url == mock.url)
    }

    @Test func revokingTheDeviceAsksForThePasswordAgain() async throws {
        let session = try await signIn(with: launchApp())

        mock.revokeAllSessions()  // Removing the device in the Jellyfin dashboard.
        let relaunched = launchApp()

        #expect(await relaunched.open(session.user.id, on: session.server.id) == false)
        #expect(relaunched.state == .choosingProfile)
        #expect(relaunched.servers.first?.isSignedIn(session.user.id) == false)
    }

    @Test func signingOutEndsTheSessionOnTheServer() async throws {
        let manager = launchApp()
        let session = try await signIn(with: manager)

        await manager.signOut()

        #expect(manager.state == .choosingProfile)
        #expect(mock.activeTokens.isEmpty)
        #expect(launchApp().servers.first?.isSignedIn(session.user.id) == false)
    }
}
