import CoreGraphics
import Foundation
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedUI

@MainActor
struct RemoteImageViewModelTests {
    let mock = MockJellyfinServer(items: [.init(name: "Arrival", imageTags: ["Primary": "p1", "Thumb": "t1", "Logo": "l1"])])
    let pipeline = ImagePipeline(configuration: MockJellyfinServer.sessionConfiguration)

    func url(_ type: String) -> URL {
        mock.url.appending(path: "Items/\(mock.items[0].id)/Images/\(type)")
    }

    var missingURL: URL {
        mock.url.appending(path: "Items/\(mock.items[0].id)/Images/Backdrop/0")
    }

    @Test func showsTheImageOnceItHasLoaded() async {
        let viewModel = RemoteImageViewModel(pipeline: pipeline)
        #expect(viewModel.image == nil)

        await viewModel.show(url("Primary"))

        #expect(viewModel.image?.width == 4)
    }

    @Test func saysWhileAnImageIsOnItsWay() async {
        let viewModel = RemoteImageViewModel(pipeline: pipeline)

        viewModel.request(url("Primary"))
        #expect(viewModel.isLoading)
        await viewModel.show(url("Primary"))

        #expect(!viewModel.isLoading)
    }

    @Test func isNotLoadingWhenTheImageCannotLoadOrThereIsNone() async {
        let viewModel = RemoteImageViewModel(pipeline: pipeline)

        await viewModel.show(missingURL)
        #expect(!viewModel.isLoading)

        await viewModel.show(nil)
        #expect(!viewModel.isLoading)
    }

    @Test func showsThePlaceholderWithoutAURL() async {
        let viewModel = RemoteImageViewModel(pipeline: pipeline)
        await viewModel.show(url("Primary"))

        await viewModel.show(nil)

        #expect(viewModel.image == nil)
    }

    @Test func showsThePlaceholderWhenTheImageCannotLoad() async {
        let viewModel = RemoteImageViewModel(pipeline: pipeline)

        await viewModel.show(missingURL)

        #expect(viewModel.image == nil)
    }

    @Test func keepsTheImageShowingWhenTheNextOneCannotLoad() async {
        let viewModel = RemoteImageViewModel(pipeline: pipeline)
        await viewModel.show(url("Primary"))
        let poster = viewModel.image

        await viewModel.show(missingURL)

        #expect(viewModel.image === poster)
    }

    @Test func startsOnAnImageAlreadyInMemory() async throws {
        let loaded = try await pipeline.image(for: url("Primary"))
        let viewModel = RemoteImageViewModel(pipeline: pipeline)

        #expect(viewModel.layers(for: url("Primary")).first?.image === loaded)
        await viewModel.show(url("Primary"))
        #expect(mock.requests.count { $0.url?.path.contains("/Images/") == true } == 1)
    }

    @Test func theLatestImageAskedForWins() async throws {
        let viewModel = RemoteImageViewModel(pipeline: pipeline)
        await viewModel.show(url("Primary"))
        let logo = try await pipeline.image(for: url("Logo"))

        // The thumbnail isn't in memory, so it's still loading when the logo, which is, shows.
        viewModel.request(url("Thumb"))
        await viewModel.show(url("Logo"))
        try await Task.sleep(for: .milliseconds(400))

        #expect(viewModel.image === logo)
    }

    @Test func askingAgainForAnImageOnItsWayDoesNotStartOver() async {
        let viewModel = RemoteImageViewModel(pipeline: pipeline)

        viewModel.request(url("Primary"))
        await viewModel.show(url("Primary"))

        #expect(viewModel.image != nil)
        #expect(mock.requests.count { $0.url?.path.hasSuffix("/Primary") == true } == 1)
    }

    @Test func askingAgainAfterAFailureTriesAgain() async {
        let viewModel = RemoteImageViewModel(pipeline: pipeline)

        await viewModel.show(missingURL)
        await viewModel.show(missingURL)

        #expect(mock.requests.count { $0.url?.path.hasSuffix("/Backdrop/0") == true } == 2)
    }

    // MARK: Fading

    @Test func fadesAPictureInOverThePlaceholder() async {
        let viewModel = RemoteImageViewModel(pipeline: pipeline)

        await viewModel.show(url("Primary"))

        #expect(viewModel.isFadingInOverPlaceholder)
        #expect(viewModel.layers.count == 1)
    }

    @Test func fadesANewImageInOverTheOneItReplaces() async throws {
        let viewModel = RemoteImageViewModel(pipeline: pipeline)
        await viewModel.show(url("Primary"))
        let poster = viewModel.image

        await viewModel.show(url("Thumb"))
        let thumbnail = viewModel.image

        // The thumbnail is on top of the poster while it fades in, then alone.
        #expect(viewModel.layers.map(\.image) == [poster, thumbnail].compactMap { $0 })
        try await Task.sleep(for: .milliseconds(400))
        #expect(viewModel.layers.map(\.image) == [thumbnail].compactMap { $0 })
    }

    @Test func keepsTheImageBeneathForAsLongAsTheFadeTakes() async throws {
        let viewModel = RemoteImageViewModel(pipeline: pipeline)
        await viewModel.show(url("Primary"))
        try await Task.sleep(for: .milliseconds(300))

        await viewModel.show(url("Thumb"), crossFade: .milliseconds(600))
        try await Task.sleep(for: .milliseconds(300))

        #expect(viewModel.layers.count == 2)
    }

    @Test func showsAnImageAlreadyInMemoryWithoutFading() async throws {
        _ = try await pipeline.image(for: url("Primary"))
        let viewModel = RemoteImageViewModel(pipeline: pipeline)

        await viewModel.show(url("Primary"))

        #expect(viewModel.layers.count == 1)
        #expect(!viewModel.isFadingInOverPlaceholder)
    }

    // MARK: Sizes

    nonisolated static let sizes: [(points: CGSize, scale: CGFloat, pixels: CGSize)] = [
        (CGSize(width: 250, height: 375), 2, CGSize(width: 500, height: 800)),
        (CGSize(width: 1920, height: 1080), 2, CGSize(width: 3900, height: 2200)),
        (CGSize(width: 0.4, height: 50), 1, CGSize(width: 100, height: 100)),
    ]

    @Test(arguments: sizes)
    func asksForWholeStepsOfPixels(_ points: CGSize, scale: CGFloat, pixels: CGSize) {
        #expect(RemoteImageViewModel.requestSize(for: points, scale: scale) == pixels)
    }
}
