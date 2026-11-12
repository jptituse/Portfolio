import Foundation
import PortfolioShared
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedJellyfinClient

struct SessionAuthorityTests {
    let client = JellyfinServerClient.mocked

    private func signedIn(on mock: MockJellyfinServer) async throws -> UserSession {
        let server = try await client.validateServer(at: mock.url)
        return try await client.signIn(to: server, username: "alex", password: "hunter2")
    }

    @Test func acceptsASessionTheServerKnows() async throws {
        let mock = MockJellyfinServer()
        let session = try await signedIn(on: mock)

        let check = await client.check(session)

        #expect(check == .valid(session.user))
        let request = try #require(mock.requests.last)
        #expect(request.url?.path == "/Users/Me")
        #expect(request.value(forHTTPHeaderField: "Authorization")?.contains("Token=\(session.accessToken)") == true)
    }

    @Test func reportsARevokedSession() async throws {
        let mock = MockJellyfinServer()
        let session = try await signedIn(on: mock)

        mock.revokeAllSessions()

        #expect(await client.check(session) == .revoked)
    }

    @Test(arguments: [MockJellyfinServer.Behavior.offline, .failing(status: 500), .failing(status: 503)])
    func cannotJudgeASessionWhenTheServerCannotAnswer(_ behavior: MockJellyfinServer.Behavior) async {
        let mock = MockJellyfinServer(behavior: behavior)
        let session = UserSession(
            server: ServerInfo(id: "s", name: "Test", version: "10.11.2", url: mock.url),
            user: User(id: "u", name: "alex", serverID: "s", primaryImageTag: nil),
            accessToken: "token"
        )

        #expect(await client.check(session) == .unavailable)
    }

    @Test func endingASessionRevokesItsToken() async throws {
        let mock = MockJellyfinServer()
        let session = try await signedIn(on: mock)
        #expect(mock.activeTokens == [session.accessToken])

        try await client.endSession(session)

        #expect(mock.activeTokens.isEmpty)
        #expect(mock.requests.last?.url?.path == "/Sessions/Logout")
        #expect(await client.check(session) == .revoked)
    }

    @Test func endingAnAlreadyRevokedSessionIsUnauthorized() async throws {
        let mock = MockJellyfinServer()
        let session = try await signedIn(on: mock)
        mock.revokeAllSessions()

        await #expect(throws: JellyfinError.unauthorized) {
            try await client.endSession(session)
        }
    }
}
