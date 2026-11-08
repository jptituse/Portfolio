import Foundation
import Testing

@testable import PortfolioShared

struct UserSessionTests {
    let session = UserSession(
        server: ServerInfo(id: "server", name: "Living Room", version: "10.11.2", url: URL(string: "http://tv.local:8096")!),
        user: User(id: "user", name: "alex", serverID: "server", primaryImageTag: nil),
        accessToken: "super-secret-token"
    )

    @Test func neverPrintsTheAccessToken() {
        for text in [String(describing: session), String(reflecting: session), "\(session)"] {
            #expect(!text.contains("super-secret-token"))
            #expect(text.contains("alex"))
        }
    }
}
