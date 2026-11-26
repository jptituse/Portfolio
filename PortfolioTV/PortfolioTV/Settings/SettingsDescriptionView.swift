import PortfolioSharedUI
import SwiftUI

/// Beside a Settings menu, as the system's Settings app draws it: a large symbol or image for the menu,
/// or for the row with focus if it has one of its own, such as a picture someone could choose, and
/// beneath it the description of the row with focus, or of the menu. Each image is drawn as it is,
/// fitted to the same largest size, with nothing behind it. The two cross-fade together when the tile
/// changes; otherwise the description changes in place.
struct SettingsDescriptionView: View {
    let tile: SettingsMenu.Tile
    let description: String?

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: Metrics.spacing) {
                tileView
                    .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                    .accessibilityHidden(true)
                Text(description ?? "")
                    .font(Metrics.descriptionFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: Metrics.descriptionWidth)
            }
            .id(tile)
            .transition(.opacity)
        }
        .animation(Metrics.crossFade, value: tile)
        .padding(.top, Metrics.topPadding)
        .accessibilityElement(children: .combine)
    }

    /// A symbol on its own, or an image fitted and rounded, as large as fits.
    @ViewBuilder private var tileView: some View {
        switch tile {
        case .symbol(let symbol):
            symbolView(symbol)
        case .image(let url, let placeholder):
            RemoteImageView(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: Metrics.cornerRadius, style: .continuous))
            } placeholder: {
                symbolView(placeholder)
            }
        case .profilePicture(let picture):
            ProfilePictureView(picture: picture)
                .clipShape(.rect(cornerRadius: Metrics.cornerRadius, style: .continuous))
        }
    }

    private func symbolView(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .fontWeight(.light)
            .foregroundStyle(.secondary)
    }
}

extension SettingsDescriptionView {
    /// Measured from the system's Settings app on an Apple TV 4K: its image 540 points across, and the
    /// description 75 points beneath, in gray.
    struct Metrics {
        /// The most an image takes up either way; each is fitted inside, keeping its shape.
        static let iconSize: CGFloat = 540
        static let cornerRadius: CGFloat = 110
        static let topPadding: CGFloat = 96
        static let spacing: CGFloat = 75
        static let descriptionWidth: CGFloat = 760
        static let descriptionFont = Font.callout
        static let crossFade = Animation.easeInOut(duration: 0.3)
    }
}
