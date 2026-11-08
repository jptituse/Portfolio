import Foundation
import PortfolioShared
import Testing

@testable import PortfolioSharedJellyfinClient

struct JellyfinServerClientTests {
    let client = JellyfinServerClient.mocked

    // MARK: Validation

    @Test func validatesASupportedServer() async throws {
        let mock = MockJellyfinServer(name: "Living Room", version: "10.11.2")

        let server = try await client.validateServer(at: mock.url)

        #expect(server == ServerInfo(id: mock.id, name: "Living Room", version: "10.11.2", url: mock.url))
        #expect(mock.requests.map(\.url?.path) == ["/System/Info/Public"])
    }

    @Test(arguments: ["10.10.0", "10.11.2", "12.4.0"])
    func acceptsEverySupportedVersion(_ version: String) async throws {
        let mock = MockJellyfinServer(version: version)
        let server = try await client.validateServer(at: mock.url)
        #expect(server.version == version)
    }

    @Test func identifiesItselfOnEveryRequest() async throws {
        let mock = MockJellyfinServer()

        _ = try await client.validateServer(at: mock.url)

        let authorization = try #require(mock.requests.first?.value(forHTTPHeaderField: "Authorization"))
        #expect(authorization.hasPrefix("MediaBrowser "))
        for field in ["Client=Portfolio", "Device=Apple TV", "DeviceId=device-123", "Version=1.0"] {
            #expect(authorization.contains(field))
        }
        #expect(!authorization.contains("Token="))
    }

    @Test func rejectsServersOlderThan10_10() async {
        let mock = MockJellyfinServer(version: "10.9.11")
        await #expect(throws: JellyfinError.unsupportedVersion(ServerVersion(major: 10, minor: 9, patch: 11))) {
            try await client.validateServer(at: mock.url)
        }
    }

    @Test func rejectsOtherMediaServers() async {
        let emby = MockJellyfinServer(version: "4.8.10.0", productName: "Emby Server")
        await #expect(throws: JellyfinError.notJellyfinServer) {
            try await client.validateServer(at: emby.url)
        }
    }

    @Test(arguments: [200, 404])
    func rejectsWebServersThatAreNotJellyfin(_ status: Int) async {
        let router = MockJellyfinServer(behavior: .otherWebServer(status: status))
        await #expect(throws: JellyfinError.notJellyfinServer) {
            try await client.validateServer(at: router.url)
        }
    }

    @Test func reportsUnreachableServers() async {
        let offline = MockJellyfinServer(behavior: .offline)
        await #expect(throws: JellyfinError.unreachable) {
            try await client.validateServer(at: offline.url)
        }
    }

    // MARK: Sign-in

    @Test func signsIn() async throws {
        let mock = MockJellyfinServer(accounts: [.init(name: "alex", password: "hunter2")])
        let server = try await client.validateServer(at: mock.url)

        let session = try await client.signIn(to: server, username: "alex", password: "hunter2")

        #expect(!session.accessToken.isEmpty)
        #expect(session.user.name == "alex")
        #expect(session.user.id == mock.accounts[0].id)
        #expect(session.server == server)
        let request = try #require(mock.requests.last)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/Users/AuthenticateByName")
    }

    @Test func signsInUsersWithoutAPassword() async throws {
        let mock = MockJellyfinServer(accounts: [.init(name: "kids", password: "")])
        let server = try await client.validateServer(at: mock.url)

        let session = try await client.signIn(to: server, username: "kids", password: "")

        #expect(session.user.name == "kids")
    }

    @Test(arguments: [("alex", "wrong"), ("nobody", "hunter2")])
    func reportsWrongCredentials(_ username: String, _ password: String) async throws {
        let mock = MockJellyfinServer(accounts: [.init(name: "alex", password: "hunter2")])
        let server = try await client.validateServer(at: mock.url)

        await #expect(throws: JellyfinError.unauthorized) {
            try await client.signIn(to: server, username: username, password: password)
        }
    }

    @Test func reportsServerFailuresDuringSignIn() async {
        let failing = MockJellyfinServer(behavior: .failing(status: 500))
        await #expect(throws: JellyfinError.serverError(statusCode: 500)) {
            try await client.signIn(to: server(at: failing.url), username: "alex", password: "hunter2")
        }
    }

    @Test func reportsAServerThatGoesOfflineBeforeSignIn() async {
        let offline = MockJellyfinServer(behavior: .offline)
        await #expect(throws: JellyfinError.unreachable) {
            try await client.signIn(to: server(at: offline.url), username: "alex", password: "hunter2")
        }
    }

    private func server(at url: URL) -> ServerInfo {
        ServerInfo(id: "server", name: "Test", version: "10.11.0", url: url)
    }
}
