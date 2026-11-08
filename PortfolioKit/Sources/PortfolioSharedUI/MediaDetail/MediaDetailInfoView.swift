import SwiftUI

/// An item's title, metadata line and overview, as shown on its platter and full-screen card.
struct MediaDetailInfoView: View {
    let viewModel: MediaDetailInfoViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.spacing) {
            Text(viewModel.title)
                .font(.title2)
                .bold()
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
    struct Metrics {
        /// Fixed, so the text lays out the same at every card size.
        static let width: CGFloat = 1100
        static let spacing: CGFloat = 16
        static let overviewLineLimit = 3
    }
}
