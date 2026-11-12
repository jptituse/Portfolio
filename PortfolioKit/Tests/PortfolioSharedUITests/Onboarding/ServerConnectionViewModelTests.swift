import Foundation
import PortfolioShared
import PortfolioSharedJellyfinClient
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedUI

@MainActor
struct ServerConnectionViewModelTests {
    let viewModel = ServerConnectionViewModel(client: .mocked)

    /// Types `address` (and `port`), connects, and returns what the step handed on, if anything.
    func connect(to address: String, port: String = "") async -> (server: ServerInfo, users: [User])? {
        var found: (ServerInfo, [User])?
        viewModel.onConnect = { found = ($0, $1) }
        viewModel.address = address
        viewModel.port = port
        await viewModel.connect()
        return found
    }

    @Test func findsTheServerAtATypedAddressWithTheUsersItLists() async {
        let mock = MockJellyfinServer(name: "Living Room", accounts: [
            .init(name: "alex", password: "hunter2"),
            .init(name: "admin", password: "secret", isHidden: true),
        ])

        let found = await connect(to: mock.url.host!)

        #expect(found?.server.name == "Living Room")
        #expect(found?.server.url == mock.url)
        #expect(found?.users.map(\.name) == ["alex"])
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.isConnecting == false)
    }

    @Test func usesAPortTypedOnItsOwn() async {
        let mock = MockJellyfinServer(url: MockJellyfinServer.uniqueURL(scheme: "http", port: 9000))

        let found = await connect(to: mock.url.host!, port: " 9000 ")

        #expect(found?.server.url == mock.url)
    }

    @Test func needsAnAddressBeforeItCanConnect() {
        #expect(viewModel.canConnect == false)
        viewModel.address = "   "
        #expect(viewModel.canConnect == false)
        viewModel.address = "tv.local"
        #expect(viewModel.canConnect)
    }

    @Test func explainsTextThatCannotBeAnAddress() async {
        #expect(await connect(to: "my server") == nil)
        #expect(viewModel.errorMessage == "Enter your server's address, such as 192.168.1.10 or jellyfin.example.com.")
    }

    @Test(arguments: ["abc", "0", "70000"])
    func explainsAPortThatCannotBeOne(_ port: String) async {
        #expect(await connect(to: "tv.local", port: port) == nil)
        #expect(viewModel.errorMessage == "The port is a number from 1 to 65535, such as 8096.")
    }

    @Test func explainsAnAddressWhereNothingAnswers() async {
        #expect(await connect(to: MockJellyfinServer.uniqueURL().host!) == nil)
        #expect(viewModel.errorMessage == "Couldn't reach a server at that address. Check the address and port, and that the server is running.")
    }

    @Test func explainsAServerThatIsNotJellyfin() async {
        let router = MockJellyfinServer(behavior: .otherWebServer(status: 404))
        #expect(await connect(to: router.url.absoluteString) == nil)
        #expect(viewModel.errorMessage == "There's a server at that address, but it isn't Jellyfin.")
    }

    @Test func explainsAJellyfinServerThatIsTooOld() async {
        let old = MockJellyfinServer(version: "10.9.11")
        #expect(await connect(to: old.url.absoluteString) == nil)
        #expect(viewModel.errorMessage == "This server runs Jellyfin 10.9.11. Portfolio needs Jellyfin 10.10 or later.")
    }

    @Test func explainsAServerThatFails() async {
        let failing = MockJellyfinServer(behavior: .failing(status: 500))
        #expect(await connect(to: failing.url.absoluteString) == nil)
        #expect(viewModel.errorMessage == "The server ran into a problem. Try again in a moment.")
    }

    @Test func clearsTheErrorOnceAnAddressWorks() async {
        let mock = MockJellyfinServer()
        _ = await connect(to: "my server")

        #expect(await connect(to: mock.url.absoluteString) != nil)
        #expect(viewModel.errorMessage == nil)
    }
}
