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

    func launchApp() async -> SessionManager {
        let manager = SessionManager(store: SessionStore(storage: keychain), authority: client)
        await manager.restore()
        return manager
    }

    func signIn(with manager: SessionManager) async throws {
        let server = try await client.validateServer(at: mock.url)
        try manager.signIn(await client.signIn(to: server, username: "alex", password: "hunter2"))
    }

    @Test func aFreshInstallStartsSignedOut() async {
        #expect(await launchApp().state == .signedOut)
    }

    @Test func signingInKeepsYouSignedInAcrossRelaunches() async throws {
        try await signIn(with: launchApp())

        let relaunched = await launchApp()

        #expect(relaunched.state.session?.user.name == "alex")
        #expect(relaunched.state.session?.server.url == mock.url)
    }

    @Test func revokingTheDeviceSignsYouOutAtTheNextLaunch() async throws {
        try await signIn(with: launchApp())

        mock.revokeAllSessions()  // Removing the device in the Jellyfin dashboard.
        let relaunched = await launchApp()

        #expect(relaunched.state == .signedOut)
        #expect(keychain.contents.isEmpty)
    }

    @Test func signingOutEndsTheSessionOnTheServer() async throws {
        let manager = await launchApp()
        try await signIn(with: manager)

        await manager.signOut()

        #expect(manager.state == .signedOut)
        #expect(mock.activeTokens.isEmpty)
        #expect(await launchApp().state == .signedOut)
    }
}
