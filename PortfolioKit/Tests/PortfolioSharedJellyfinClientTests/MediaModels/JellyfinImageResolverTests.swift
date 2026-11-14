import Foundation
import PortfolioShared
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedJellyfinClient

struct JellyfinImageResolverTests {
    let resolver = JellyfinImageResolver(server: .sample(url: "https://example.com/jellyfin"))
    let item = MediaItem(
        id: "movie-1",
        name: "Arrival",
        kind: .movie,
        images: [.primary: "p1", .logo: "l1", .thumb: "t1", .backdrop(): "b0", .backdrop(index: 1): "b1"]
    )
    let size = CGSize(width: 500, height: 750)

    @Test(arguments: [
        (MediaImageKind.primary, "Primary", "p1"),
        (.thumb, "Thumb", "t1"),
        (.backdrop(), "Backdrop/0", "b0"),
        (.backdrop(index: 1), "Backdrop/1", "b1"),
    ])
    func asksForAnImageCoveringItsFrameAtFullQuality(_ kind: MediaImageKind, path: String, tag: String) throws {
        let url = try #require(resolver.url(for: item, kind, pixelSize: size))

        #expect(url.absoluteString
            == "https://example.com/jellyfin/Items/movie-1/Images/\(path)?tag=\(tag)&fillWidth=500&fillHeight=750&quality=100")
    }

    @Test func asksForALogoFittingInsideItsFrame() throws {
        let url = try #require(resolver.url(for: item, .logo, pixelSize: CGSize(width: 800, height: 300)))

        #expect(url.absoluteString == "https://example.com/jellyfin/Items/movie-1/Images/Logo?tag=l1&maxWidth=800&maxHeight=300&quality=100")
    }

    @Test func roundsFractionalPixelsUp() throws {
        let url = try #require(resolver.url(for: item, .primary, pixelSize: CGSize(width: 499.2, height: 748.5)))
        #expect(url.query()?.contains("fillWidth=500&fillHeight=749") == true)
    }

    @Test func namesNoFormatSoTransparentImagesStayTransparent() throws {
        let url = try #require(resolver.url(for: item, .logo, pixelSize: size))
        #expect(url.query()?.contains("format") == false)
    }

    @Test(arguments: [MediaImageKind.primary, .thumb, .logo, .backdrop(), .backdrop(index: 2)])
    func hasNoURLForAnImageTheItemDoesNotHave(_ kind: MediaImageKind) {
        let bare = MediaItem(id: "movie-2", name: "Bare", kind: .movie, images: [.backdrop(): "b0", .backdrop(index: 1): "b1"])
        let expectsURL = kind == .backdrop()
        #expect((resolver.url(for: bare, kind, pixelSize: size) != nil) == expectsURL)
    }

    @Test func pointsAtTheItemAnImageBelongsTo() throws {
        let episode = MediaItem(id: "episode", name: "The Bridge", kind: .episode, images: [
            .backdrop(): MediaImageReference(tag: "sb", ownerID: "show"),
        ])

        let url = try #require(resolver.url(for: episode, .backdrop(), pixelSize: size))

        #expect(url.path() == "/jellyfin/Items/show/Images/Backdrop/0")
        #expect(url.query()?.contains("tag=sb") == true)
    }

    @Test func pointsAtAServerWithoutAPath() throws {
        let resolver = JellyfinImageResolver(server: .sample(url: "http://192.168.1.10:8096"))
        let url = try #require(resolver.url(for: item, .primary, pixelSize: size))
        #expect(url.absoluteString.hasPrefix("http://192.168.1.10:8096/Items/movie-1/Images/Primary?"))
    }
}
