import Foundation
import PortfolioShared
import PortfolioSharedTestSupport
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

    // MARK: Finding the server at a typed address

    /// The address someone would type for a server on `host`: no scheme, no port.
    func typed(_ host: String) throws -> ServerAddress {
        try #require(ServerAddress(host))
    }

    @Test func usesHTTPSWhenTheServerAnswersThere() async throws {
        let mock = MockJellyfinServer()

        let server = try await client.validateServer(at: typed(mock.url.host!))

        #expect(server.url == mock.url)
        #expect(mock.requests.count == 1)
    }

    @Test func fallsBackToJellyfinsHTTPPort() async throws {
        let mock = MockJellyfinServer(url: MockJellyfinServer.uniqueURL(scheme: "http", port: 8096))

        let server = try await client.validateServer(at: typed(mock.url.host!))

        #expect(server.url == mock.url)
    }

    @Test func passesOverAnotherWebServerOnTheHTTPSPort() async throws {
        let host = MockJellyfinServer.uniqueURL().host!
        let router = MockJellyfinServer(url: URL(string: "https://\(host)")!, behavior: .otherWebServer(status: 200))
        let jellyfin = MockJellyfinServer(url: URL(string: "http://\(host):8096")!)

        let server = try await client.validateServer(at: typed(host))

        #expect(server.url == jellyfin.url)
        #expect(router.requests.count == 1)
    }

    @Test func reportsTheMostTellingFailure() async throws {
        let host = MockJellyfinServer.uniqueURL().host!
        let router = MockJellyfinServer(url: URL(string: "https://\(host)")!, behavior: .otherWebServer(status: 404))
        let address = try typed(host)

        // Nothing answers on HTTP, but the router answering on HTTPS says more.
        await #expect(throws: JellyfinError.notJellyfinServer) {
            try await client.validateServer(at: address)
        }
        #expect(router.requests.count == 1)
    }

    @Test func reportsAnAddressWhereNothingAnswers() async throws {
        let address = try typed(MockJellyfinServer.uniqueURL().host!)
        await #expect(throws: JellyfinError.unreachable) {
            try await client.validateServer(at: address)
        }
    }

    @Test func stopsAtAJellyfinServerThatIsTooOld() async throws {
        let host = MockJellyfinServer.uniqueURL().host!
        let old = MockJellyfinServer(url: URL(string: "https://\(host)")!, version: "10.9.11")
        let other = MockJellyfinServer(url: URL(string: "http://\(host):8096")!)
        let address = try typed(host)

        await #expect(throws: JellyfinError.unsupportedVersion(ServerVersion(major: 10, minor: 9, patch: 11))) {
            try await client.validateServer(at: address)
        }
        #expect(old.requests.count == 1)
        #expect(other.requests.isEmpty)
    }

    // MARK: The sign-in screen

    @Test func listsTheUsersTheServerShowsOnItsSignInScreen() async throws {
        let mock = MockJellyfinServer(accounts: [
            .init(name: "alex", password: "hunter2", imageTag: "avatar-1"),
            .init(name: "kids", password: ""),
            .init(name: "admin", password: "secret", isHidden: true),
        ])

        let users = try await client.listedUsers(on: server(at: mock.url))

        #expect(users.map(\.name) == ["alex", "kids"])
        #expect(users.map(\.id) == [mock.accounts[0].id, mock.accounts[1].id])
        #expect(users.map(\.primaryImageTag) == ["avatar-1", nil])
        #expect(users.map(\.hasPassword) == [true, false])
    }

    @Test func readsTheServersBranding() async throws {
        let mock = MockJellyfinServer(loginDisclaimer: " **Family only.** ", splashscreenEnabled: true)

        let branding = try await client.branding(of: server(at: mock.url))

        #expect(branding.loginMessage == "**Family only.**")
        #expect(branding.splashImageURL?.absoluteString == "\(mock.url.absoluteString)/Branding/Splashscreen?format=Png")
    }

    @Test func usesTheLargestIconTheWebClientOffers() async throws {
        let mock = MockJellyfinServer()

        let branding = try await client.branding(of: server(at: mock.url))

        #expect(branding.iconURL?.absoluteString == "\(mock.url.absoluteString)/web/favicons/touchicon512.png")
    }

    @Test func hasOnlyTheIconWhereTheServerSetsNothingElse() async throws {
        let mock = MockJellyfinServer()

        let branding = try await client.branding(of: server(at: mock.url))

        #expect(branding.loginMessage == nil)
        #expect(branding.splashImageURL == nil)
        #expect(branding.iconURL != nil)
    }

    @Test func hasNoIconWithoutAWebClient() async throws {
        let mock = MockJellyfinServer(loginDisclaimer: "Welcome.", hostsWebClient: false)

        let branding = try await client.branding(of: server(at: mock.url))

        #expect(branding.iconURL == nil)
        #expect(branding.loginMessage == "Welcome.")
    }

    @Test func asksForAUsersPictureAtFullQualityEvenBehindAReverseProxyPath() throws {
        let server = server(at: URL(string: "https://example.com/jellyfin")!)
        let user = User(id: "user-1", name: "Alex", serverID: "server", primaryImageTag: "abc")

        let url = try #require(client.pictureURL(for: user, on: server))

        #expect(url.absoluteString == "https://example.com/jellyfin/UserImage?userId=user-1&tag=abc&format=Png")
    }

    @Test func hasNoPictureForAUserWithoutOne() {
        let user = User(id: "user-1", name: "Alex", serverID: "server", primaryImageTag: nil)
        #expect(client.pictureURL(for: user, on: server(at: URL(string: "https://example.com")!)) == nil)
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
