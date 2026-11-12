import SwiftUI

/// A person's picture in a circle, with their initials until it loads or if they have none. It fills
/// whatever frame it's given.
public struct AvatarView: View {
    let pictureURL: URL?
    let initials: String

    public init(pictureURL: URL?, initials: String) {
        self.pictureURL = pictureURL
        self.initials = initials
    }

    public var body: some View {
        // FIXME: Load pictures through the shared image pipeline, with caching, once it exists (#9).
        AsyncImage(url: pictureURL) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            initialsView
        }
        .clipShape(Circle())
    }

    /// The initials are sized to the circle, so they read the same in a big tile or a small sidebar.
    private var initialsView: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            Circle()
                .fill(.gray.opacity(Metrics.placeholderOpacity))
                .overlay {
                    Text(initials)
                        .font(.system(size: diameter * Metrics.initialsShare, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(Metrics.initialsMinimumScale)
                        .padding(diameter * Metrics.initialsPaddingShare)
                }
        }
    }
}

extension AvatarView {
    struct Metrics {
        static let placeholderOpacity = 0.4
        /// The initials' size as a share of the circle's diameter.
        static let initialsShare = 0.4
        static let initialsMinimumScale = 0.5
        static let initialsPaddingShare = 0.12
    }
}

#Preview {
    AvatarView(pictureURL: nil, initials: "AR")
        .frame(width: 200, height: 200)
}
