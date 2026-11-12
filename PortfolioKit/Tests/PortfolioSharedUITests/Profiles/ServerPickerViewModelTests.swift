import Foundation
import PortfolioShared
import PortfolioSharedJellyfinClient
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedUI

/// Picking a server for someone not on the profile picker, against mock Jellyfin servers.
@MainActor
struct ServerPickerViewModelTests {
    let livingRoom = MockJellyfinServer(name: "Living Room")
    let office = MockJellyfinServer(name: "Office", hostsWebClient: false)
    let sessionManager = SessionManager(store: MediaServerStore(storage: InMemorySecureStorage()), authority: JellyfinServerClient.mocked)
    let viewModel: ServerPickerViewModel

    init() {
        viewModel = ServerPickerViewModel(client: .mocked, sessionManager: sessionManager)
    }

    /// Adds `mock` to this device, as signing someone in to it does.
    func add(_ mock: MockJellyfinServer) async throws {
        let server = try await JellyfinServerClient.mocked.validateServer(at: mock.url)
        try sessionManager.signIn(.sample(userID: "user-\(mock.name)", server: server))
    }

    @Test func asksWhichServer() {
        #expect(viewModel.title == "Which server are you on?")
    }

    @Test func showsEachAddedServerWithItsAddress() async throws {
        try await add(livingRoom)
        try await add(office)

        #expect(viewModel.tiles.map(\.name) == ["Living Room", "Office"])
        #expect(viewModel.tiles.map(\.detail) == [livingRoom.url.host(), office.url.host()])
        #expect(viewModel.tiles.map(\.initials) == ["LR", "O"])
    }

    @Test func showsEachServersIconWhereItsWebClientOffersOne() async throws {
        try await add(livingRoom)
        try await add(office)

        await viewModel.loadIcons()

        #expect(viewModel.tiles[0].pictureURL?.absoluteString == "\(livingRoom.url.absoluteString)/web/favicons/touchicon512.png")
        #expect(viewModel.tiles[1].pictureURL == nil)
    }

    @Test func handsOnTheServerPickedOrAddingAnother() async throws {
        try await add(livingRoom)
        var picked: [String] = []
        var added = 0
        viewModel.onPick = { picked.append($0.name) }
        viewModel.onAddServer = { added += 1 }

        viewModel.pick(try #require(viewModel.tiles.first).id)
        viewModel.pick("nowhere")
        viewModel.addServer()

        #expect(picked == ["Living Room"])
        #expect(added == 1)
    }
}
