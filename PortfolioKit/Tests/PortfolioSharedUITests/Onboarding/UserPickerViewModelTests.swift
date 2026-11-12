import Foundation
import PortfolioShared
import PortfolioSharedJellyfinClient
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedUI

@MainActor
struct UserPickerViewModelTests {
    let alex = User(id: "alex", name: "Alex Rivera", serverID: "server-1", primaryImageTag: "avatar")
    let kids = User(id: "kids", name: "kids", serverID: "server-1", primaryImageTag: nil)
    let viewModel: UserPickerViewModel

    init() {
        viewModel = UserPickerViewModel(server: .sample(), users: [alex, kids], client: .mocked)
    }

    @Test func asksWhoIsSigningInToTheServer() {
        #expect(viewModel.title == "Who's signing in to Living Room?")
    }

    @Test func showsEveryoneTheServerListsWithTheirPicture() {
        let tiles = viewModel.tiles

        #expect(tiles.map(\.name) == ["Alex Rivera", "kids"])
        #expect(tiles.map(\.initials) == ["AR", "K"])
        #expect(tiles[0].pictureURL == JellyfinServerClient.mocked.pictureURL(for: alex, on: .sample()))
        #expect(tiles[1].pictureURL == nil)
    }

    @Test func handsOnThePersonPickedOrSomeoneElse() {
        var picks: [User?] = []
        viewModel.onPick = { picks.append($0) }

        viewModel.pick("kids")
        viewModel.pickSomeoneElse()
        viewModel.pick("nobody")

        #expect(picks == [kids, nil])
    }
}
