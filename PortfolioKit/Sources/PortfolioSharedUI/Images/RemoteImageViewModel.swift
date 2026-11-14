import CoreGraphics
import Foundation
import Observation

/// What a `RemoteImageView` shows: the images it has loaded, or nothing, so the placeholder shows.
///
/// A new URL replaces the image only once its image has loaded, so the placeholder never shows in
/// between, and it fades in on top of the one it replaces, which goes once it's covered. If loading
/// fails, the image already showing stays; with none, the placeholder does.
@MainActor
@Observable
public final class RemoteImageViewModel {
    /// An image to draw.
    public struct Layer: Identifiable {
        public let image: CGImage
        /// Keeps the image in memory while it's drawn, so other views can show it at once too.
        let lease: ImageLease?
        public var id: ObjectIdentifier { ObjectIdentifier(image) }
    }

    /// The images to draw, bottom to top: the one showing, and while it fades in, a new one on top.
    public private(set) var layers: [Layer] = []
    /// Whether a first image is fading in over the placeholder.
    public private(set) var isFadingInOverPlaceholder = false
    /// Whether an image is on its way, so the placeholder can show that it's loading.
    public private(set) var isLoading = false

    @ObservationIgnored private let pipeline: ImagePipeline
    /// The latest request, while it loads.
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var fading: Task<Void, Never>?
    /// The URL asked for last, and the one whose image is on top.
    @ObservationIgnored private var requestedURL: URL?
    @ObservationIgnored private var shownURL: URL?

    public init(pipeline: ImagePipeline = .shared) {
        self.pipeline = pipeline
    }

    /// The newest image: the one showing, or the one fading in over it.
    public var image: CGImage? {
        layers.last?.image
    }

    /// What to draw for `url`: the layers, or with none yet, the image for `url` if it's already in
    /// memory, so a view showing an image the app already has never starts on its placeholder.
    public func layers(for url: URL?) -> [Layer] {
        if layers.isEmpty, let cached = url.flatMap(pipeline.cachedImage) {
            // Only until the request for it, which follows at once, holds it.
            return [Layer(image: cached, lease: nil)]
        }
        return layers
    }

    /// Asks for the image at `url`, or the placeholder for nil, in place of anything asked for before.
    /// An image in memory shows at once; any other loads, and fades in once it has. Asking again for
    /// what's showing or on its way does nothing; asking again after it failed tries again.
    ///
    /// - Parameter crossFade: how long an image that arrives later takes to fade in, so the one beneath
    ///   stays until it's covered.
    public func request(_ url: URL?, crossFade: Duration = defaultCrossFade, priority: ImagePriority = .normal) {
        if url == requestedURL, url == shownURL || loading != nil { return }
        loading?.cancel()
        loading = nil
        requestedURL = url
        guard let url else {
            setLoading(false)
            display(nil, url: nil, fades: false, crossFade: crossFade)
            return
        }
        if let cached = pipeline.cachedImage(for: url) {
            setLoading(false)
            // A view without an image yet already draws one in memory, so it doesn't fade in.
            display(cached, url: url, fades: !layers.isEmpty, crossFade: crossFade)
            return
        }
        setLoading(true)
        loading = Task {
            defer {
                // A cancelled request has been replaced already.
                if !Task.isCancelled {
                    loading = nil
                    setLoading(false)
                }
            }
            guard let loaded = try? await pipeline.image(for: url, priority: priority), !Task.isCancelled else { return }
            display(loaded, url: url, fades: true, crossFade: crossFade)
        }
    }

    /// Asks for the image at `url`, and returns once it has loaded or failed.
    public func show(_ url: URL?, crossFade: Duration = defaultCrossFade) async {
        request(url, crossFade: crossFade)
        await loading?.value
    }

    private func setLoading(_ isLoading: Bool) {
        if self.isLoading != isLoading { self.isLoading = isLoading }
    }

    private func display(_ newImage: CGImage?, url: URL?, fades: Bool, crossFade: Duration) {
        // A fade under way ends at once.
        fading?.cancel()
        fading = nil
        isFadingInOverPlaceholder = false
        layers = Array(layers.suffix(1))
        shownURL = url
        guard let newImage else {
            layers = []
            return
        }
        let layer = Layer(image: newImage, lease: url.map { pipeline.lease(newImage, for: $0) })
        guard fades else {
            layers = [layer]
            return
        }
        isFadingInOverPlaceholder = layers.isEmpty
        layers.append(layer)
        fading = Task {
            try? await Task.sleep(for: crossFade)
            guard !Task.isCancelled else { return }
            isFadingInOverPlaceholder = false
            layers = [layer]
        }
    }

    /// The size in pixels to ask for an image drawn at `size` points, rounded up to whole steps, so
    /// sizes that differ a little share one image.
    public nonisolated static func requestSize(for size: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: roundUp(size.width * scale), height: roundUp(size.height * scale))
    }

    private nonisolated static func roundUp(_ pixels: CGFloat) -> CGFloat {
        (pixels / sizeStep).rounded(.up) * sizeStep
    }

    /// How long an image that arrives later takes to fade in, unless the view says otherwise.
    public nonisolated static let defaultCrossFade = Duration.milliseconds(200)
    nonisolated static let sizeStep: CGFloat = 100
}
