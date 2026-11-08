import PortfolioShared
import SwiftUI

/// An item's card, in any form. Its artwork stretches to whatever frame it's given. Its labels (the
/// poster title, or the details once it's bigger) don't change along with it: whoever moves the card
/// hides them as it starts to move (`Metrics.labelFadeOut`) and shows them once it has stopped
/// (`Metrics.labelFadeIn`). The details keep a fixed width, so they never reflow while a platter grows
/// to full screen.
public struct MediaCardView: View {
    let viewModel: MediaCardViewModel

    @Environment(\.viewState) private var layer

    public init(viewModel: MediaCardViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let form = viewModel.form(in: layer)
        let showsDetails = viewModel.showsDetails(in: layer)
        artwork
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(Metrics.scrimOpacity)], startPoint: .center, endPoint: .bottom)
                    .opacity(showsDetails ? 1 : 0)
            }
            .overlay(alignment: .bottomLeading) {
                Text(viewModel.title)
                    .font(.caption)
                    .bold()
                    .lineLimit(Metrics.titleLineLimit)
                    .padding(Metrics.titlePadding)
                    .opacity(viewModel.showsTitle(in: layer) ? 1 : 0)
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

    // FIXME: Load the item's artwork from the server instead of drawing this gradient (#9): its portrait
    // poster in a row, and its landscape thumbnail once `isExtended` is set and in the larger forms.
    private var artwork: some View {
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
