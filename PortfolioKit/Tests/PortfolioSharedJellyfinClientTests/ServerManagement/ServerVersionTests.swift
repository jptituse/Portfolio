import Testing

@testable import PortfolioSharedJellyfinClient

struct ServerVersionTests {
    @Test(arguments: [
        ("10.10.7", ServerVersion(major: 10, minor: 10, patch: 7)),
        ("10.11", ServerVersion(major: 10, minor: 11, patch: 0)),
        ("10.11.0-rc1", ServerVersion(major: 10, minor: 11, patch: 0)),
        ("4.8.10.0", ServerVersion(major: 4, minor: 8, patch: 10)),
    ])
    func parses(_ input: String, _ expected: ServerVersion) {
        #expect(ServerVersion(input) == expected)
    }

    @Test(arguments: ["", "10", "abc.def", "ten.eleven.0"])
    func rejectsMalformedVersions(_ input: String) {
        #expect(ServerVersion(input) == nil)
    }

    @Test func requiresAtLeast10_10() {
        #expect(ServerVersion("10.9.11")?.isSupported == false)
        #expect(ServerVersion("10.10.0")?.isSupported == true)
        #expect(ServerVersion("10.11.2")?.isSupported == true)
        #expect(ServerVersion("11.0.0")?.isSupported == true)
    }

    @Test func comparesComponentsNumerically() {
        #expect(ServerVersion("10.9.0")! < ServerVersion("10.10.0")!)
        #expect(ServerVersion("10.10.9")! < ServerVersion("10.10.10")!)
    }
}
