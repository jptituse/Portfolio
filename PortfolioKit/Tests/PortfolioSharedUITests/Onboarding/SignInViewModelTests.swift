import Foundation
import PortfolioShared
import PortfolioSharedJellyfinClient
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedUI

@MainActor
struct SignInViewModelTests {
    let mock = MockJellyfinServer(name: "Living Room", accounts: [
        .init(name: "alex", password: "hunter2", imageTag: "avatar"),
        .init(name: "kids", password: ""),
    ])
    let keychain: InMemorySecureStorage
    let sessionManager: SessionManager

    init() {
        let keychain = InMemorySecureStorage()
        self.keychain = keychain
        sessionManager = SessionManager(store: MediaServerStore(storage: keychain), authority: JellyfinServerClient.mocked)
    }

    var server: ServerInfo {
        get async throws { try await JellyfinServerClient.mocked.validateServer(at: mock.url) }
    }

    /// The sign-in step for one of the mock's users, picked by name, or for someone else.
    func makeViewModel(picking name: String? = nil, on server: ServerInfo? = nil) async throws -> SignInViewModel {
        var target = server
        if target == nil {
            target = try await self.server
        }
        let found = try #require(target)
        var user: User?
        if let name {
            user = try await JellyfinServerClient.mocked.listedUsers(on: found).first { $0.name == name }
        }
        return SignInViewModel(server: found, user: user, client: .mocked, sessionManager: sessionManager)
    }

    func signIn(_ viewModel: SignInViewModel, password: String) async {
        viewModel.password = password
        await viewModel.signIn()
    }

    // MARK: Who's signing in

    @Test func someonePickedOnlyNeedsTheirPassword() async throws {
        let viewModel = try await makeViewModel(picking: "alex")

        #expect(viewModel.title == "alex")
        #expect(viewModel.prompt == "Enter your password for Living Room.")
        #expect(viewModel.asksForUsername == false)
        #expect(viewModel.asksForPassword)
        #expect(viewModel.tile?.pictureURL?.query()?.contains("tag=avatar") == true)
        #expect(viewModel.canSignIn)
    }

    @Test func someonePickedWithoutAPasswordJustSignsIn() async throws {
        let viewModel = try await makeViewModel(picking: "kids")

        #expect(viewModel.asksForPassword == false)
        #expect(viewModel.prompt == "Your account on Living Room doesn't need a password.")

        await viewModel.signIn()

        #expect(sessionManager.state.session?.user.name == "kids")
    }

    @Test func someoneElseTypesTheirUsernameToo() async throws {
        let viewModel = try await makeViewModel()

        #expect(viewModel.title == "Sign in to Living Room")
        #expect(viewModel.prompt == "Enter your username and password.")
        #expect(viewModel.asksForUsername)
        #expect(viewModel.asksForPassword)
        #expect(viewModel.tile == nil)
        #expect(viewModel.canSignIn == false)
        viewModel.username = "  "
        #expect(viewModel.canSignIn == false)
        viewModel.username = "alex"
        #expect(viewModel.canSignIn)
    }

    // MARK: Signing in

    @Test func signingInSavesTheServerAndSignsTheAppIn() async throws {
        let viewModel = try await makeViewModel(picking: "alex")

        await signIn(viewModel, password: "hunter2")

        #expect(sessionManager.state.session?.user.name == "alex")
        #expect(sessionManager.servers.map(\.server.name) == ["Living Room"])
        #expect(!keychain.contents.isEmpty)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isSigningIn == false)
    }

    @Test func someoneElseSignsInWithTheUsernameTheyTyped() async throws {
        let viewModel = try await makeViewModel()
        viewModel.username = " alex "

        await signIn(viewModel, password: "hunter2")

        #expect(sessionManager.state.session?.user.name == "alex")
    }

    @Test func aWrongPasswordSaysSoAndClearsIt() async throws {
        let picked = try await makeViewModel(picking: "alex")
        await signIn(picked, password: "wrong")

        #expect(picked.errorMessage == "That password is incorrect.")
        #expect(picked.password.isEmpty)
        #expect(sessionManager.state.session == nil)

        let someoneElse = try await makeViewModel()
        someoneElse.username = "alex"
        await signIn(someoneElse, password: "wrong")

        #expect(someoneElse.errorMessage == "The username or password is incorrect.")
        #expect(someoneElse.username == "alex")
    }

    @Test func aServerThatStoppedAnsweringSaysSo() async throws {
        let offline = MockJellyfinServer(behavior: .offline)
        let viewModel = try await makeViewModel(on: ServerInfo(id: "server", name: "Living Room", version: "10.11.2", url: offline.url))
        viewModel.username = "alex"

        await signIn(viewModel, password: "hunter2")

        #expect(viewModel.errorMessage == "Couldn't reach Living Room. Check that it's still running, and try again.")
    }

    @Test func aServerThatFailsSaysSo() async throws {
        let failing = MockJellyfinServer(behavior: .failing(status: 500))
        let viewModel = try await makeViewModel(on: ServerInfo(id: "server", name: "Living Room", version: "10.11.2", url: failing.url))
        viewModel.username = "alex"

        await signIn(viewModel, password: "hunter2")

        #expect(viewModel.errorMessage == "Living Room ran into a problem signing you in. Try again in a moment.")
    }

    @Test func aSignInThatCannotBeSavedSaysSoAndStaysSignedOut() async throws {
        let viewModel = try await makeViewModel(picking: "alex")
        keychain.failAllCalls(with: TestError("Keychain unavailable"))

        await signIn(viewModel, password: "hunter2")

        #expect(viewModel.errorMessage == "Your sign-in couldn't be saved on this device. Try again.")
        #expect(sessionManager.state.session == nil)
    }

    // MARK: Branding

    @Test func showsTheServersBranding() async throws {
        let branded = MockJellyfinServer(loginDisclaimer: "**Family** only.", splashscreenEnabled: true)
        let viewModel = try await makeViewModel(on: JellyfinServerClient.mocked.validateServer(at: branded.url))

        await viewModel.loadBranding()

        #expect(viewModel.loginMessage.map { String($0.characters) } == "Family only.")
        #expect(viewModel.splashImageURL?.absoluteString == "\(branded.url.absoluteString)/Branding/Splashscreen?format=Png")
        #expect(viewModel.serverIconURL?.absoluteString == "\(branded.url.absoluteString)/web/favicons/touchicon512.png")
    }

    @Test func showsTheServersNameWithoutBranding() async throws {
        let plain = MockJellyfinServer(name: "Living Room", hostsWebClient: false)
        let viewModel = try await makeViewModel(on: JellyfinServerClient.mocked.validateServer(at: plain.url))

        await viewModel.loadBranding()

        #expect(viewModel.loginMessage == nil)
        #expect(viewModel.splashImageURL == nil)
        #expect(viewModel.serverIconURL == nil)
        #expect(viewModel.serverName == "Living Room")
        #expect(viewModel.serverDetails == "Jellyfin 10.11.2 at \(plain.url.absoluteString)")
    }
}
