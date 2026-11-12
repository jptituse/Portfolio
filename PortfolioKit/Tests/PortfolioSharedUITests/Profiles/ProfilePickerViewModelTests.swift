import Foundation
import PortfolioShared
import PortfolioSharedJellyfinClient
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedUI

/// The profile picker, against mock Jellyfin servers and an in-memory Keychain.
@MainActor
struct ProfilePickerViewModelTests {
    let livingRoom = MockJellyfinServer(name: "Living Room", accounts: [
        .init(name: "alex", password: "hunter2", imageTag: "avatar"),
        .init(name: "sam", password: "secret"),
    ])
    let sessionManager = SessionManager(store: MediaServerStore(storage: InMemorySecureStorage()), authority: JellyfinServerClient.mocked)
    let viewModel: ProfilePickerViewModel

    init() {
        viewModel = ProfilePickerViewModel(client: .mocked, sessionManager: sessionManager)
    }

    /// Signs `name` in to `server` and back out to the picker, leaving them signed in on this device.
    func addProfile(_ name: String, password: String, on server: MockJellyfinServer) async throws {
        let client = JellyfinServerClient.mocked
        let info = try await client.validateServer(at: server.url)
        try sessionManager.signIn(await client.signIn(to: info, username: name, password: password))
        sessionManager.restore()
    }

    func tile(_ name: String) throws -> ProfileTile {
        try #require(viewModel.tiles.first { $0.name == name })
    }

    @Test func showsEveryoneOnEveryServerWithTheServersName() async throws {
        let office = MockJellyfinServer(name: "Office", accounts: [.init(name: "alex", password: "work")])
        try await addProfile("alex", password: "hunter2", on: livingRoom)
        try await addProfile("alex", password: "work", on: office)

        #expect(viewModel.tiles.map(\.name) == ["alex", "alex"])
        #expect(viewModel.tiles.map(\.detail) == ["Living Room", "Office"])
        #expect(Set(viewModel.tiles.map(\.id)).count == 2)
        #expect(viewModel.tiles[0].pictureURL?.query()?.contains("tag=avatar") == true)
    }

    @Test func openingASignedInProfileSignsTheAppIn() async throws {
        try await addProfile("alex", password: "hunter2", on: livingRoom)

        await viewModel.open(try tile("alex").id)

        #expect(sessionManager.state.session?.user.name == "alex")
        #expect(viewModel.isOpening(try tile("alex").id) == false)
    }

    @Test func aSignedOutProfileSignsInFirst() async throws {
        try await addProfile("alex", password: "hunter2", on: livingRoom)
        await viewModel.refresh()
        var asked: [String] = []
        viewModel.onSignIn = { server, user in asked.append("\(user.name) on \(server.name)") }

        await viewModel.open(try tile("sam").id)

        #expect(asked == ["sam on Living Room"])
        #expect(sessionManager.state == .choosingProfile)
    }

    @Test func aProfileTheServerSignedOutSignsInAgain() async throws {
        try await addProfile("alex", password: "hunter2", on: livingRoom)
        livingRoom.revokeAllSessions()
        var asked: [String] = []
        viewModel.onSignIn = { _, user in asked.append(user.name) }

        await viewModel.open(try tile("alex").id)

        #expect(asked == ["alex"])
        #expect(sessionManager.state == .choosingProfile)
    }

    @Test func startsOnTheProfileOpenedLast() async throws {
        let office = MockJellyfinServer(name: "Office", accounts: [.init(name: "sam", password: "work")])
        try await addProfile("alex", password: "hunter2", on: livingRoom)
        try await addProfile("sam", password: "work", on: office)

        // Sam opened last; the picker starts on Sam, not on the first profile.
        #expect(viewModel.initialFocus == viewModel.tiles.last?.id)
        #expect(viewModel.initialFocus != viewModel.tiles.first?.id)
    }

    @Test func startsWhereTheSystemChoosesWithoutAProfileOpenedLast() {
        #expect(viewModel.initialFocus == nil)
    }

    @Test func refreshingShowsWhoTheServersListNow() async throws {
        try await addProfile("alex", password: "hunter2", on: livingRoom)
        #expect(viewModel.tiles.map(\.name) == ["alex"])

        await viewModel.refresh()

        #expect(viewModel.tiles.map(\.name) == ["alex", "sam"])
    }

    @Test func aServerThatCannotBeReachedKeepsItsProfiles() async throws {
        let session = UserSession.sample(server: ServerInfo(id: "gone", name: "Gone", version: "10.11.2", url: MockJellyfinServer.uniqueURL()))
        try sessionManager.signIn(session)
        sessionManager.restore()

        await viewModel.refresh()

        #expect(viewModel.tiles.map(\.name) == ["alex"])
    }

    @Test func someoneElseHandsOff() {
        var asked = 0
        viewModel.onSomeoneElse = { asked += 1 }

        viewModel.someoneElse()

        #expect(asked == 1)
    }
}
