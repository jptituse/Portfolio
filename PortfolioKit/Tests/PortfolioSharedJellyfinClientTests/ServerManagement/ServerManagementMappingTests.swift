import Foundation
import JellyfinAPI
import PortfolioShared
import Testing

@testable import PortfolioSharedJellyfinClient

struct ServerManagementMappingTests {
    @Test func mapsAUser() throws {
        let result = try Fixture.decode(AuthenticationResult.self, from: "authenticate-by-name")
        let user = try #require(result.user.flatMap(User.init))

        #expect(user == User(
            id: "6c1e2f8a9b0d4c3e8f7a6b5c4d3e2f1a",
            name: "alex",
            serverID: "f2a4c1d3e5b64a7f9c8d0e1f2a3b4c5d",
            primaryImageTag: "a1b2c3d4e5f6"
        ))
    }

    @Test func mapsPublicSystemInfo() throws {
        let dto = try Fixture.decode(PublicSystemInfo.self, from: "system-info-public")
        let url = URL(string: "http://192.168.1.20:8096")!

        let server = try ServerInfo(dto, url: url)

        #expect(server == ServerInfo(id: "f2a4c1d3e5b64a7f9c8d0e1f2a3b4c5d", name: "Living Room", version: "10.11.2", url: url))
    }
}
