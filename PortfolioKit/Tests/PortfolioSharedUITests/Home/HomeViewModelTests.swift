import Foundation
import PortfolioShared
import PortfolioSharedJellyfinClient
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedUI

/// Home, against a mock Jellyfin server.
@MainActor
struct HomeViewModelTests {
    let client = JellyfinServerClient.mocked

    func signIn(to mock: MockJellyfinServer) async throws -> UserSession {
        let server = try await client.validateServer(at: mock.url)
        return try await client.signIn(to: server, username: "alex", password: "hunter2")
    }

    func latestRequests(to mock: MockJellyfinServer) -> Int {
        mock.requests.count { $0.url?.path == "/Items/Latest" }
    }

    @Test func showsWhatWasAddedMostRecentlyInARow() async throws {
        let mock = MockJellyfinServer(items: [.init(name: "Arrival"), .init(name: "Severance", type: "Series")])
        let home = HomeViewModel(client: client, session: try await signIn(to: mock))

        await home.load()

        #expect(home.groups.map(\.title) == ["Recently Added"])
        #expect(home.groups.first?.items.map(\.name) == ["Arrival", "Severance"])
        #expect(home.message == nil)
        #expect(!home.isLoading)
    }

    @Test func drawsArtworkFromTheProfilesServer() async throws {
        let mock = MockJellyfinServer()
        let session = try await signIn(to: mock)

        let home = HomeViewModel(client: client, session: session)

        #expect((home.images as? JellyfinImageResolver)?.server == session.server)
    }

    @Test func loadsAgainEachTimeItShowsAndPicksUpWhatsNew() async throws {
        let mock = MockJellyfinServer(items: [.init(name: "Arrival")])
        let home = HomeViewModel(client: client, session: try await signIn(to: mock))
        await home.load()

        mock.items.insert(.init(name: "Dune"), at: 0)
        await home.load()

        #expect(latestRequests(to: mock) == 2)
        #expect(home.groups.first?.items.map(\.name) == ["Dune", "Arrival"])
    }

    @Test func keepsItsRowsWhenNothingChanged() async throws {
        let mock = MockJellyfinServer(items: [.init(name: "Arrival")])
        let home = HomeViewModel(client: client, session: try await signIn(to: mock))
        await home.load()
        let rows = home.groups

        await home.load()

        #expect(home.groups == rows)
        #expect(home.message == nil)
    }

    @Test func keepsShowingItsRowsWhileLoadingAgain() async throws {
        let mock = MockJellyfinServer(items: [.init(name: "Arrival")])
        let home = HomeViewModel(client: client, session: try await signIn(to: mock))
        await home.load()

        let again = Task { await home.load() }
        await Task.yield()

        #expect(!home.isLoading)
        #expect(!home.groups.isEmpty)
        await again.value
    }

    @Test func keepsItsRowsWhenItCannotBringThemUpToDate() async throws {
        let mock = MockJellyfinServer(name: "Living Room", items: [.init(name: "Arrival")])
        let home = HomeViewModel(client: client, session: try await signIn(to: mock))
        await home.load()
        mock.revokeAllSessions()

        await home.load()

        #expect(home.groups.first?.items.map(\.name) == ["Arrival"])
        #expect(home.message == "Living Room no longer accepts this sign-in. Switch profiles to sign in again.")
    }

    @Test func keepsLoadingWhenTheViewThatAskedGoesAway() async throws {
        let mock = MockJellyfinServer(items: [.init(name: "Arrival")])
        let home = HomeViewModel(client: client, session: try await signIn(to: mock))

        // SwiftUI cancels a view's task when it replaces the view, and the new one asks again.
        let replacedView = Task { await home.load() }
        await Task.yield()
        replacedView.cancel()
        await home.load()

        #expect(home.groups.first?.items.map(\.name) == ["Arrival"])
        #expect(home.message == nil)
        #expect(latestRequests(to: mock) == 1)
    }

    @Test func saysWhenNothingHasBeenAddedYet() async throws {
        let mock = MockJellyfinServer(items: [])
        let home = HomeViewModel(client: client, session: try await signIn(to: mock))

        await home.load()

        #expect(home.groups.isEmpty)
        #expect(home.message == "Nothing has been added to your libraries yet.")
        #expect(!home.canRetry)
    }

    @Test func explainsAServerItCannotReach() async {
        let home = HomeViewModel(client: client, session: .sample(server: ServerInfo(
            id: "gone",
            name: "Living Room",
            version: "10.11.2",
            url: MockJellyfinServer.uniqueURL()
        )))

        await home.load()

        #expect(home.groups.isEmpty)
        #expect(home.message == "Couldn't reach Living Room. Check that it's still running, and try again.")
        #expect(home.canRetry)
    }

    @Test func explainsASignInTheServerNoLongerAccepts() async throws {
        let mock = MockJellyfinServer(name: "Living Room")
        let home = HomeViewModel(client: client, session: try await signIn(to: mock))
        mock.revokeAllSessions()

        await home.load()

        #expect(home.message == "Living Room no longer accepts this sign-in. Switch profiles to sign in again.")
    }

    @Test func triesAgainAfterAFailure() async {
        let mock = MockJellyfinServer(name: "Living Room", behavior: .failing(status: 500))
        let home = HomeViewModel(client: client, session: .sample(server: ServerInfo(id: "s", name: "Living Room", version: "10.11.2", url: mock.url)))
        await home.load()
        #expect(home.message == "Living Room ran into a problem loading what's new. Try again in a moment.")

        await home.load()

        #expect(latestRequests(to: mock) == 2)
    }

    @Test func hasNothingToLoadWithoutAProfile() async {
        let home = HomeViewModel(client: client, session: nil)

        await home.load()

        #expect(home.groups.isEmpty)
        #expect(home.images == nil)
    }
}
