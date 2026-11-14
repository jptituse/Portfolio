import SwiftUI

/// An item's logo (or title, without one), metadata line and overview, as shown on its platter and
/// full-screen card, and on Home's banner, which moves it to where the full-screen card shows it.
public struct MediaDetailInfoView: View {
    let viewModel: MediaDetailInfoViewModel

    init(viewModel: MediaDetailInfoViewModel) {
        self.viewModel = viewModel
    }

    /// The details of `card`'s item, the very same its card shows.
    public init(card: MediaCardViewModel) {
        self.init(viewModel: card.detailInfo)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spacing) {
            if let logoURL = viewModel.logoURL {
                // What's open or on Home's banner, so it goes ahead of posters waiting to download.
                RemoteImageView(url: logoURL, alignment: .bottomLeading, priority: .high) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .frame(
                    width: MediaCardView.Metrics.detailsLogoSize.width,
                    height: MediaCardView.Metrics.detailsLogoSize.height,
                    alignment: .bottomLeading
                )
                .accessibilityElement()
                .accessibilityLabel(viewModel.title)
            } else {
                Text(viewModel.title)
                    .font(.title2)
                    .bold()
            }
            if let metadata = viewModel.metadata {
                Text(metadata)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let overview = viewModel.overview {
                Text(overview)
                    .font(.body)
                    .lineLimit(Metrics.overviewLineLimit)
            }
        }
    }
}

extension MediaDetailInfoView {
    public struct Metrics {
        /// Fixed, so the text lays out the same at every card size.
        public static let width: CGFloat = 1100
        static let spacing: CGFloat = 16
        static let overviewLineLimit = 3
    }
}
