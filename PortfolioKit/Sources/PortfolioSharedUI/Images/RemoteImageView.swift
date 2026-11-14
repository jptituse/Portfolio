import SwiftUI

/// An image loaded from a URL through the shared `ImagePipeline`. It takes the space it's offered and
/// draws `content` there once the image has loaded, or `placeholder` while it loads or if it can't. An
/// image the app already has in memory shows at once; one that arrives later fades in.
///
/// It never changes the image it draws in place: SwiftUI blends the two while the view's frame moves,
/// the old one at its old size. A new image comes as a view of its own on top, and the one beneath goes
/// once it's covered.
public struct RemoteImageView<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let alignment: Alignment
    private let crossFade: Duration
    private let priority: ImagePriority
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    @State private var viewModel = RemoteImageViewModel()
    @Environment(\.displayScale) private var displayScale

    /// - Parameters:
    ///   - alignment: where `content` sits in the space offered, if it doesn't fill it.
    ///   - crossFade: how long an image that arrives later takes to fade in.
    ///   - priority: how soon it's wanted, if it has to wait to download.
    public init(
        url: URL?,
        alignment: Alignment = .center,
        crossFade: Duration = RemoteImageViewModel.defaultCrossFade,
        priority: ImagePriority = .normal,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.alignment = alignment
        self.crossFade = crossFade
        self.priority = priority
        self.content = content
        self.placeholder = placeholder
    }

    public var body: some View {
        let layers = viewModel.layers(for: url)
        Color.clear
            .overlay(alignment: alignment) {
                ZStack(alignment: alignment) {
                    if layers.isEmpty || viewModel.isFadingInOverPlaceholder {
                        placeholder()
                            .environment(\.isLoadingImage, viewModel.isLoading)
                            .transition(.identity)
                    }
                    ForEach(layers) { layer in
                        content(Image(decorative: layer.image, scale: displayScale))
                            .transition(.asymmetric(insertion: arrival(of: layer, in: layers), removal: .identity))
                    }
                }
            }
            .onChange(of: url, initial: true) { viewModel.request(url, crossFade: crossFade, priority: priority) }
    }

    /// How a layer appears: fading in, opacity alone, if it arrives on top of another image or of the
    /// placeholder, and at once otherwise.
    private func arrival(of layer: RemoteImageViewModel.Layer, in layers: [RemoteImageViewModel.Layer]) -> AnyTransition {
        let isFadingIn = layers.count > 1 || viewModel.isFadingInOverPlaceholder
        return isFadingIn && layer.id == layers.last?.id ? .opacity.animation(.easeInOut(duration: crossFade.seconds)) : .identity
    }
}

private extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
