import Foundation
import Testing

@testable import PortfolioSharedJellyfinClient

struct ServerAddressTests {
    func candidates(_ text: String) -> [String]? {
        ServerAddress(text)?.candidates.map(\.absoluteString)
    }

    @Test func triesHTTPSThenJellyfinsHTTPPortForABareHost() {
        #expect(candidates("192.168.1.10") == ["https://192.168.1.10", "http://192.168.1.10:8096"])
        #expect(candidates("jellyfin.example.com") == ["https://jellyfin.example.com", "http://jellyfin.example.com:8096"])
    }

    @Test func keepsATypedPortForBothSchemes() {
        #expect(candidates("192.168.1.10:8920") == ["https://192.168.1.10:8920", "http://192.168.1.10:8920"])
    }

    @Test func usesAPortGivenOnItsOwn() {
        #expect(ServerAddress("192.168.1.10", port: 9000)?.candidates.map(\.absoluteString) == ["https://192.168.1.10:9000", "http://192.168.1.10:9000"])
        #expect(ServerAddress("http://tv.local:8096", port: 9000)?.candidates.map(\.absoluteString) == ["http://tv.local:9000"])
    }

    @Test func usesAnAddressWithASchemeExactlyAsTyped() {
        #expect(candidates("http://192.168.1.10") == ["http://192.168.1.10"])
        #expect(candidates("https://media.example.com:8443") == ["https://media.example.com:8443"])
        #expect(candidates("HTTPS://media.example.com") == ["https://media.example.com"])
    }

    @Test func keepsAReverseProxyPathWithoutItsTrailingSlash() {
        #expect(candidates("example.com/jellyfin/") == ["https://example.com/jellyfin", "http://example.com:8096/jellyfin"])
        #expect(candidates("https://example.com/") == ["https://example.com"])
    }

    @Test func ignoresSpacesAroundTheAddress() {
        #expect(candidates("  tv.local \n") == ["https://tv.local", "http://tv.local:8096"])
    }

    @Test(arguments: ["", "   ", "my server", "ftp://example.com", "https://", "http://:8096"])
    func rejectsTextThatIsNotAnAddress(_ text: String) {
        #expect(ServerAddress(text) == nil)
    }
}
