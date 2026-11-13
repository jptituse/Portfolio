import Foundation
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedUI

struct ImagePipelineTests {
    let mock = MockJellyfinServer(items: [.init(name: "Arrival", imageTags: ["Primary": "p1"])])
    let pipeline = ImagePipeline(configuration: MockJellyfinServer.sessionConfiguration)

    var posterURL: URL {
        mock.url.appending(path: "Items/\(mock.items[0].id)/Images/Primary")
    }

    var imageRequests: Int {
        mock.requests.count { $0.url?.path.contains("/Images/") == true }
    }

    @Test func loadsAndDecodesAnImage() async throws {
        let image = try await pipeline.image(for: posterURL)

        #expect(image.width == 4)
        #expect(image.height == 6)
    }

    @Test func keepsDecodedImagesInMemory() async throws {
        #expect(pipeline.cachedImage(for: posterURL) == nil)

        let first = try await pipeline.image(for: posterURL)
        let second = try await pipeline.image(for: posterURL)

        #expect(second === first)
        #expect(pipeline.cachedImage(for: posterURL) === first)
        #expect(imageRequests == 1)
    }

    @Test func downloadsOnceForEveryoneAskingAtOnce() async throws {
        async let first = pipeline.image(for: posterURL)
        async let second = pipeline.image(for: posterURL)

        #expect(try await first === second)
        #expect(imageRequests == 1)
    }

    @Test func reportsAnImageTheServerDoesNotHave() async {
        let missing = mock.url.appending(path: "Items/\(mock.items[0].id)/Images/Logo")

        await #expect(throws: ImagePipeline.LoadingError.status(404)) { try await pipeline.image(for: missing) }
    }

    @Test func reportsDataThatIsNotAnImage() async {
        let broken = MockJellyfinServer(items: [.init(name: "Arrival", imageTags: ["Primary": "p1"])], imageData: Data("not an image".utf8))
        let url = broken.url.appending(path: "Items/\(broken.items[0].id)/Images/Primary")

        await #expect(throws: ImagePipeline.LoadingError.undecodable) { try await pipeline.image(for: url) }
    }

    @Test func triesAFailedImageAgainNextTime() async {
        let missing = mock.url.appending(path: "Items/\(mock.items[0].id)/Images/Logo")

        _ = try? await pipeline.image(for: missing)
        _ = try? await pipeline.image(for: missing)

        #expect(imageRequests == 2)
    }
}
