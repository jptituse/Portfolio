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

    /// - Parameter artworkFrame: where the landscape art is, in the card's coordinates. Without one, it
    ///   fills the card. It animates along with the card's own frame, in the same animation, so the two
    ///   never drift apart: computing it afresh on every frame of the motion instead put it a few
    ///   frames ahead of the card on an Apple TV, the poster showing around it.
    public init(viewModel: MediaCardViewModel, artworkFrame: CGRect? = nil) {
        self.viewModel = viewModel
        self.artworkFrame = artworkFrame
    }

    public var body: some View {
        let form = viewModel.form(in: layer)
        let showsDetails = viewModel.showsDetails(in: layer)
        Color.clear
            // The poster fills the card, so it grows and shrinks with it.
            .overlay {
                poster
            }
            // The landscape art has the frame it's given, such as a platter's as big as the screen.
            .overlay(alignment: .topLeading) {
                landscapeArtwork
                    .frame(width: artworkFrame?.width, height: artworkFrame?.height)
                    .offset(x: artworkFrame?.minX ?? 0, y: artworkFrame?.minY ?? 0)
            }
            .overlay {
                Self.detailsScrim
                    .opacity(showsDetails ? 1 : 0)
            }
            .overlay {
                // Keeps the progress readable over bright artwork.
                LinearGradient(colors: [.clear, .black.opacity(Metrics.progressScrimOpacity)], startPoint: .center, endPoint: .bottom)
                    .opacity(viewModel.showsProgressIndicator(in: layer) ? 1 : 0)
            }
            .overlay(alignment: .bottomLeading) {
                // Drawn ahead of time along with the landscape art, so it's there as the poster widens.
                if viewModel.loadsLandscapeArtwork(in: layer) {
                    let logoSize = viewModel.showsProgress ? Metrics.compactLogoSize : Metrics.logoSize
                    VStack(alignment: .leading, spacing: Metrics.progressSpacing) {
                        logo
                            .frame(width: logoSize.width, height: logoSize.height, alignment: .bottomLeading)
                            .opacity(viewModel.showsLogo(in: layer) ? 1 : 0)
                        if viewModel.showsProgress {
                            MediaProgressIndicatorView(
                                progress: viewModel.progress,
                                episodeLabel: viewModel.episodeLabel,
                                timeLeftLabel: viewModel.timeLeftLabel
                            )
                            .opacity(viewModel.showsProgressIndicator(in: layer) ? 1 : 0)
                        }
                    }
                    .padding(Metrics.logoPadding)
                    // The poster already reads as its title. Text appearing and disappearing inside it
                    // took the focused poster out of the accessibility tree's focus.
                    .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottomLeading) {
                MediaDetailInfoView(viewModel: viewModel.detailInfo)
                    .frame(width: MediaDetailInfoView.Metrics.width, alignment: .leading)
                    .padding(.leading, Metrics.detailsLeadingPadding(for: form))
                    .padding(.bottom, Metrics.detailsBottomPadding)
                    .opacity(showsDetails ? 1 : 0)
            }
            .overlay {
                Color.black.opacity(viewModel.isDimmed(in: layer) ? Metrics.dimmedOpacity : 0)
            }
            .clipShape(UnevenRoundedRectangle(cornerRadii: Metrics.cornerRadii(for: form)))
    }

    /// The item's poster, filling the card. It and the landscape art over it are always laid out with the
    /// card, so they move and grow with it; nothing is swapped while it moves.
    private var poster: some View {
        RemoteImageView(url: viewModel.posterArtworkURL) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            ImagePlaceholderView()
        }
    }

    /// The landscape art, over the poster while the card is wider. It's only drawn while it shows or
    /// loads ahead of time.
    @ViewBuilder private var landscapeArtwork: some View {
        ZStack {
            if viewModel.loadsLandscapeArtwork(in: layer) {
                // Until it has loaded, the poster shows through. It's what a card grows into, so it
                // goes ahead of posters waiting to download.
                RemoteImageView(url: viewModel.landscapeArtworkURL, priority: .high) { image in
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

    /// How the landscape art fades over the poster: quickly, early in the motion, both ways. A poster
    /// filling a card that's getting wider zooms in, so the landscape art covers it before it has grown
    /// much; shrinking back, the poster shows again early, and shrinks with the card.
    private func fade(showing: Bool) -> Animation {
        showing ? Metrics.landscapeFadeIn : Metrics.landscapeFadeOut
    }

    /// Darkens the bottom of a card showing its details, so they read over any artwork.
    public static var detailsScrim: some View {
        LinearGradient(colors: [.clear, .black.opacity(Metrics.scrimOpacity)], startPoint: .center, endPoint: .bottom)
            .allowsHitTesting(false)
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

}
