import PortfolioSharedUI
import SwiftUI

/// A column of facts at the end of an item's page, such as Information: its title, then each fact's
/// label in gray over its value, as the TV app's.
struct MediaDetailFactsColumnView: View {
    let column: MediaDetailViewModel.Column

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.factSpacing) {
            Text(column.title)
                .font(.headline)
                .bold()
                .padding(.bottom, Metrics.titleSpacing)
            ForEach(column.facts) { fact in
                VStack(alignment: .leading, spacing: Metrics.labelSpacing) {
                    Text(fact.label)
                        .foregroundStyle(.secondary)
                    Text(fact.value)
                        .lineLimit(Metrics.valueLineLimit)
                }
                .font(.caption)
            }
        }
        .frame(width: Metrics.width, alignment: .topLeading)
    }
}

extension MediaDetailFactsColumnView {
    struct Metrics {
        /// Four across the screen, inside its margins.
        static let width: CGFloat = 380
        static let titleSpacing: CGFloat = 8
        static let factSpacing: CGFloat = 20
        static let labelSpacing: CGFloat = 4
        static let valueLineLimit = 4
    }
}
