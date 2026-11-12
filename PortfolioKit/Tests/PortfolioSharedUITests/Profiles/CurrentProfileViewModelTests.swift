import Foundation
import PortfolioShared
import PortfolioSharedJellyfinClient
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedUI

@MainActor
struct CurrentProfileViewModelTests {
    let sessionManager = SessionManager(store: MediaServerStore(storage: InMemorySecureStorage()), authority: JellyfinServerClient.mocked)
    let viewModel: CurrentProfileViewModel

    init() {
        viewModel = CurrentProfileViewModel(client: .mocked, sessionManager: sessionManager)
    }

    @Test func showsWhoIsSignedInAndOnWhichServer() throws {
        let alex = User(id: "alex", name: "Alex Rivera", serverID: "server-1", primaryImageTag: "avatar")
        let session = UserSession(server: .sample(), user: alex, accessToken: "token")
        try sessionManager.signIn(session)

        let tile = try #require(viewModel.tile)

        #expect(tile.name == "Alex Rivera")
        #expect(tile.detail == "Living Room")
        #expect(tile.initials == "AR")
        #expect(tile.pictureURL == JellyfinServerClient.mocked.pictureURL(for: alex, on: .sample()))
    }

    @Test func showsNobodyWithoutAnOpenProfile() {
        #expect(viewModel.tile == nil)
    }

    @Test func switchingGoesBackToThePickerAndStaysSignedIn() throws {
        try sessionManager.signIn(.sample())

        viewModel.switchProfile()

        #expect(sessionManager.state == .choosingProfile)
        #expect(sessionManager.servers.first?.isSignedIn("user-1") == true)
        #expect(viewModel.tile == nil)
    }
}
