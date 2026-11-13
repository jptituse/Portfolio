import SwiftUI

extension EnvironmentValues {
    /// Whether the image a placeholder stands in for is on its way. `RemoteImageView` sets it for its
    /// placeholder.
    @Entry public var isLoadingImage = false
}

/// What shows where an image will be: a translucent gray, with a soft shimmer passing over it while the
/// image loads. Without an image to load, it's just the gray. The shimmer stays off with Reduce Motion.
public struct ImagePlaceholderView: View {
    @Environment(\.isLoadingImage) private var isLoading
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        Rectangle()
            .fill(.white.opacity(Metrics.grayOpacity))
            .overlay {
                if isLoading && !reduceMotion {
                    shimmer
                }
            }
            .clipped()
    }

    /// A band of light sweeping across, again and again. Drawn from the time rather than animated, so
    /// it never joins an animation moving the card it's in.
    private var shimmer: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { proxy in
                let period = Metrics.shimmerPeriod
                let progress = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                let band = proxy.size.width * Metrics.bandShare
                LinearGradient(
                    colors: [.clear, .white.opacity(Metrics.shimmerOpacity), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: band)
                .offset(x: -band + (proxy.size.width + band * 2) * progress)
            }
        }
    }
}

extension ImagePlaceholderView {
    struct Metrics {
        /// The gray of the system's resting platters: white at this opacity over the background.
        static let grayOpacity = 0.1
        static let shimmerOpacity = 0.12
        /// The band's width as a share of the placeholder's.
        static let bandShare = 0.6
        /// Seconds for one sweep.
        static let shimmerPeriod = 1.6
    }
}

#Preview {
    ImagePlaceholderView()
        .environment(\.isLoadingImage, true)
        .frame(width: 250, height: 375)
}
