import Foundation
import PortfolioShared
import PortfolioSharedJellyfinClient
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedUI

/// Everything before someone is signed in, against a mock Jellyfin server and an in-memory Keychain.
@MainActor
struct ProfilesViewModelTests {
    let mock = MockJellyfinServer(name: "Living Room", accounts: [
        .init(name: "alex", password: "hunter2"),
        .init(name: "sam", password: "secret"),
    ])
    let sessionManager = SessionManager(store: MediaServerStore(storage: InMemorySecureStorage()), authority: JellyfinServerClient.mocked)

    func makeViewModel() -> ProfilesViewModel {
        ProfilesViewModel(client: .mocked, sessionManager: sessionManager)
    }

    /// Adds the mock server by its address, as the server step does.
    func findServer(with viewModel: ProfilesViewModel) async throws {
        viewModel.addServerByAddress()
        guard case .server(let server) = viewModel.path.last else {
            Issue.record("The server step didn't come next")
            return
        }
        server.address = mock.url.absoluteString
        await server.connect()
    }

    func lastSignIn(of viewModel: ProfilesViewModel) throws -> SignInViewModel {
        guard case .signIn(let signIn) = viewModel.path.last else {
            throw TestError("The sign-in step isn't showing")
        }
        return signIn
    }

    // MARK: Steps

    @Test func eachStepIsEqualOnlyToItself() {
        let viewModel = makeViewModel()
        viewModel.addServerByAddress()
        viewModel.addServerByAddress()

        // Two server steps with the same content are still two entries.
        #expect(viewModel.path[0] == viewModel.path[0])
        #expect(viewModel.path[0] != viewModel.path[1])
        #expect(Set(viewModel.path).count == 2)
        #expect(ProfilesViewModel.Step.welcome == .welcome)
        #expect(ProfilesViewModel.Step.welcome != viewModel.path[0])
    }

    // MARK: Where it starts

    @Test func aFreshInstallStartsOnTheWelcomeScreen() {
        let viewModel = makeViewModel()
        #expect(viewModel.picker == nil)
        #expect(viewModel.path.isEmpty)
    }

    @Test func startsOnTheProfilePickerOnceAServerIsAdded() throws {
        try sessionManager.signIn(.sample())
        sessionManager.restore()

        #expect(makeViewModel().picker != nil)
    }

    // MARK: Adding a server

    @Test func findingTheServerAsksWhoIsSigningIn() async throws {
        let viewModel = makeViewModel()

        try await findServer(with: viewModel)

        guard case .users(let users) = viewModel.path.last else {
            Issue.record("The user picker didn't come next")
            return
        }
        #expect(users.tiles.map(\.name) == ["alex", "sam"])
    }

    @Test func pickingSomeoneAsksForTheirPassword() async throws {
        let viewModel = makeViewModel()
        try await findServer(with: viewModel)
        guard case .users(let users) = viewModel.path.last else { return }

        users.pick(try #require(users.tiles.first { $0.name == "sam" }).id)

        #expect(try lastSignIn(of: viewModel).title == "sam")
    }

    @Test func aServerThatListsNobodyAsksForAUsername() async throws {
        let hidden = MockJellyfinServer(accounts: [.init(name: "alex", password: "hunter2", isHidden: true)])
        let viewModel = makeViewModel()
        viewModel.addServerByAddress()
        guard case .server(let server) = viewModel.path.last else { return }
        server.address = hidden.url.absoluteString

        await server.connect()

        #expect(try lastSignIn(of: viewModel).asksForUsername)
        #expect(viewModel.path.count == 2)
    }

    @Test func aFreshInstallReachesASignedInSession() async throws {
        let viewModel = makeViewModel()
        try await findServer(with: viewModel)
        guard case .users(let users) = viewModel.path.last else { return }
        users.pick(try #require(users.tiles.first { $0.name == "alex" }).id)
        let signIn = try lastSignIn(of: viewModel)
        signIn.password = "hunter2"

        await signIn.signIn()

        #expect(sessionManager.state.session?.user.name == "alex")
        #expect(sessionManager.state.session?.server.url == mock.url)
    }

    // MARK: From the profile picker

    /// The server picker that "Someone Else" on the profile picker leads to.
    func pickServer(with viewModel: ProfilesViewModel) throws -> ServerPickerViewModel {
        viewModel.picker?.someoneElse()
        guard case .servers(let servers) = viewModel.path.last else {
            throw TestError("The server picker didn't come next")
        }
        return servers
    }

    @Test func someoneElsePicksTheirServerFirst() async throws {
        try sessionManager.signIn(.sample(server: await JellyfinServerClient.mocked.validateServer(at: mock.url)))
        sessionManager.restore()
        let viewModel = makeViewModel()

        let servers = try pickServer(with: viewModel)

        #expect(servers.tiles.map(\.name) == ["Living Room"])
        #expect(viewModel.path.count == 1)
    }

    @Test func someoneElseOnAnAddedServerTypesTheirUsername() async throws {
        try sessionManager.signIn(.sample(server: await JellyfinServerClient.mocked.validateServer(at: mock.url)))
        sessionManager.restore()
        let viewModel = makeViewModel()
        let servers = try pickServer(with: viewModel)

        servers.pick(try #require(servers.tiles.first).id)

        let signIn = try lastSignIn(of: viewModel)
        #expect(signIn.asksForUsername)
        #expect(signIn.title == "Sign in to Living Room")
    }

    @Test func someoneElseOnAnotherServerStartsAtTheWelcomeScreen() throws {
        try sessionManager.signIn(.sample())
        sessionManager.restore()
        let viewModel = makeViewModel()
        let servers = try pickServer(with: viewModel)

        servers.addServer()

        #expect(viewModel.path == [.servers(servers), .welcome])
    }

    @Test func aSignedOutProfileAsksForTheirPassword() async throws {
        try sessionManager.signIn(.sample(server: await JellyfinServerClient.mocked.validateServer(at: mock.url)))
        await sessionManager.signOut()
        let viewModel = makeViewModel()
        let picker = try #require(viewModel.picker)

        await picker.open(try #require(picker.tiles.first).id)

        #expect(try lastSignIn(of: viewModel).title == "alex")
    }

    #if DEBUG
    @Test func theSampleSessionSignsInWithoutAServer() {
        makeViewModel().continueWithSampleSession()
        #expect(sessionManager.state == .signedIn(.preview))
    }
    #endif
}
