import PortfolioShared
import SwiftUI

/// An item's card, in any form. Its artwork fills the card, keeping its proportions, unless it's given a
/// frame of its own, such as a platter's artwork as big as the screen; the card shows the part it
/// covers. The artwork is the poster, with the landscape art over it once the card is wider: it fades
/// in or out in whatever animation changes the card's form, so the picture changes as the card moves.
/// Its labels (the poster title, or the details once it's bigger) don't change along with it:
/// whoever moves the card hides them as it starts to move (`Metrics.labelFadeOut`) and shows them once
/// it has stopped (`Metrics.labelFadeIn`). The details keep a fixed width, so they never reflow while a
/// platter grows to full screen.
public struct MediaCardView: View {
    let viewModel: MediaCardViewModel
    let artworkFrame: CGRect?

    @Environment(\.viewState) private var layer

    /// - Parameter artworkFrame: where the artwork is, in the card's coordinates. Without one, it fills
    ///   the card.
    public init(viewModel: MediaCardViewModel, artworkFrame: CGRect? = nil) {
        self.viewModel = viewModel
        self.artworkFrame = artworkFrame
    }

    public var body: some View {
        let form = viewModel.form(in: layer)
        let showsDetails = viewModel.showsDetails(in: layer)
        Color.clear
            .overlay(alignment: .topLeading) {
                artwork
                    .frame(width: artworkFrame?.width, height: artworkFrame?.height)
                    .offset(x: artworkFrame?.minX ?? 0, y: artworkFrame?.minY ?? 0)
            }
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(Metrics.scrimOpacity)], startPoint: .center, endPoint: .bottom)
                    .opacity(showsDetails ? 1 : 0)
            }
            .overlay(alignment: .bottomLeading) {
                // Drawn ahead of time along with the landscape art, so it's there as the poster widens.
                if viewModel.loadsLandscapeArtwork(in: layer) {
                    logo
                        .frame(width: Metrics.logoSize.width, height: Metrics.logoSize.height, alignment: .bottomLeading)
                        .padding(Metrics.logoPadding)
                        .opacity(viewModel.showsLogo(in: layer) ? 1 : 0)
                        // The poster already reads as its title. Text appearing and disappearing inside
                        // it took the focused poster out of the accessibility tree's focus.
                        .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottomLeading) {
                MediaDetailInfoView(viewModel: viewModel.detailInfo)
                    .frame(width: MediaDetailInfoView.Metrics.width, alignment: .leading)
                    .padding(.leading, Metrics.detailsLeadingPadding(for: form))
                    .padding(.bottom, Metrics.detailsBottomPadding(for: form))
                    .opacity(showsDetails ? 1 : 0)
            }
            .overlay {
                Color.black.opacity(viewModel.isDimmed(in: layer) ? Metrics.dimmedOpacity : 0)
            }
            .clipShape(UnevenRoundedRectangle(cornerRadii: Metrics.cornerRadii(for: form)))
    }

    /// The item's artwork, filling its frame: the poster, and the landscape art over it while the card
    /// is wider. Both are always laid out with the card, so they move and grow with it; nothing is
    /// swapped while it moves. The landscape art is only drawn while it shows or loads ahead of time.
    private var artwork: some View {
        ZStack {
            RemoteImageView(url: viewModel.posterArtworkURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                placeholderArtwork
            }
            if viewModel.loadsLandscapeArtwork(in: layer) {
                // Until it has loaded, the poster shows through.
                RemoteImageView(url: viewModel.landscapeArtworkURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.clear
                }
                // Its own timing for the fade, opacity alone: the images still move with the card.
                .animation(fade(showing: viewModel.showsLandscapeArtwork(in: layer))) { content in
                    content.opacity(viewModel.showsLandscapeArtwork(in: layer) ? 1 : 0)
                }
                // It goes at once: a view fading out keeps its last layout, while the card may be moving.
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }
        }
    }

    /// How the landscape art fades over the poster. A poster filling a card that's getting wider zooms
    /// in, so the landscape art covers it quickly, before it has grown much. As the card narrows or
    /// shrinks back to a poster, it uncovers it as the card moves.
    private func fade(showing: Bool) -> Animation {
        showing ? Metrics.landscapeFadeIn : Metrics.landscapeFadeOut
    }

    /// The item's logo, small, or its title if it has none.
    @ViewBuilder private var logo: some View {
        if let logoURL = viewModel.logoArtworkURL {
            RemoteImageView(url: logoURL, alignment: .bottomLeading) { image in
                image
                    .resizable()
                    .scaledToFit()
                    .shadow(color: .black.opacity(Metrics.logoShadowOpacity), radius: Metrics.logoShadowRadius)
            } placeholder: {
                Color.clear
            }
        } else {
            Text(viewModel.title)
                .font(.caption)
                .bold()
                .lineLimit(Metrics.titleLineLimit)
                .shadow(color: .black.opacity(Metrics.logoShadowOpacity), radius: Metrics.logoShadowRadius)
        }
    }

    /// A color while the artwork loads, or for an item without any.
    private var placeholderArtwork: some View {
        let hue = viewModel.artworkHue
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: Metrics.lightColor.saturation, brightness: Metrics.lightColor.brightness),
                Color(hue: hue, saturation: Metrics.darkColor.saturation, brightness: Metrics.darkColor.brightness),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
