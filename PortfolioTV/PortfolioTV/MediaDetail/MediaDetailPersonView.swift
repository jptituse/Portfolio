import PortfolioSharedUI
import SwiftUI

/// Someone in an item's cast and crew, or found by Search: their picture in a circle that grows with
/// focus, their name, and the character they play or their part, if there's one, as the TV app's.
struct MediaDetailPersonView: View {
    let name: String
    /// The character they play, or their part: "Director".
    let role: String?
    let pictureURL: URL?

    var body: some View {
        // FIXME: Open the person's page, with what they're in (#44).
        Button {} label: {
            Label(name: name, role: role, pictureURL: pictureURL)
        }
        .buttonStyle(MediaCardButtonStyle())
        .accessibilityElement(children: .combine)
    }
}

extension MediaDetailPersonView {
    /// The picture grows and casts a shadow with focus, the names moving down with it. The system's
    /// highlight drew a rounded square around the circle.
    struct Label: View {
        let name: String
        let role: String?
        let pictureURL: URL?
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            VStack(spacing: Metrics.textSpacing) {
                picture
                    .frame(width: Metrics.size, height: Metrics.size)
                    .clipShape(.circle)
                    .scaleEffect(isFocused ? Metrics.focusedScale : 1)
                    .shadow(color: .black.opacity(isFocused ? Metrics.shadowOpacity : 0), radius: Metrics.shadowRadius, y: Metrics.shadowOffset)
                    .padding(.bottom, Metrics.pictureSpacing + (isFocused ? Metrics.size * (Metrics.focusedScale - 1) / 2 : 0))
                Text(name)
                    .font(.callout)
                if let role {
                    Text(role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .frame(width: Metrics.size)
            .animation(Metrics.focusMotion, value: isFocused)
        }

        /// "AA" for Amy Adams, for someone without a picture.
        static func initials(of name: String) -> String {
            name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        }

        private var picture: some View {
            RemoteImageView(url: pictureURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                ZStack {
                    Color.white.opacity(Metrics.placeholderOpacity)
                    Text(Self.initials(of: name))
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    struct Metrics {
        static let size = MediaDetailPageView.Metrics.pictureSize.width
        static let pictureSpacing: CGFloat = 12
        static let textSpacing: CGFloat = 4
        static let placeholderOpacity = 0.1
        /// As much as the TV app's grow.
        static let focusedScale: CGFloat = 1.15
        static let shadowOpacity = 0.4
        static let shadowRadius: CGFloat = 20
        static let shadowOffset: CGFloat = 12
        static var focusMotion: Animation { .easeOut(duration: 0.2) }
    }
}
