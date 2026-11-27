import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// The full text of a tile or column on an item's page, in a panel over it, as the TV app's. Select or
/// Back closes it.
struct MediaDetailPanelView: View {
    let panel: MediaDetailPanel
    let onClose: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(Metrics.dimming)
                .ignoresSafeArea()
            // A button, so it takes focus, and Select closes it.
            Button(action: onClose) {
                VStack(alignment: .leading, spacing: Metrics.spacing) {
                    VStack(alignment: .leading, spacing: Metrics.subtitleSpacing) {
                        Text(panel.title)
                            .font(.title3)
                            .bold()
                        if let subtitle = panel.subtitle {
                            Text(subtitle)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let text = panel.text {
                        Text(text)
                            .font(.callout)
                    }
                    ForEach(panel.facts) { fact in
                        VStack(alignment: .leading, spacing: Metrics.labelSpacing) {
                            Text(fact.label)
                                .foregroundStyle(.secondary)
                            Text(fact.value)
                        }
                        .font(.callout)
                    }
                }
                .padding(Metrics.padding)
                .frame(width: Metrics.width, alignment: .leading)
                .background(.regularMaterial, in: .rect(cornerRadius: Metrics.cornerRadius))
            }
            .buttonStyle(MediaCardButtonStyle())
            .focused($isFocused)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .defaultFocus($isFocused, true)
        .onAppear { isFocused = true }
    }
}

/// The full text of a tile or column on an item's page: the overview, or a column's facts.
struct MediaDetailPanel: Equatable {
    let title: String
    let subtitle: String?
    let text: String?
    let facts: [MediaDetailViewModel.Fact]
    /// What opened it, which focus goes back to.
    let opener: MediaDetailFocus

    /// The item's title, genres, tagline and overview.
    static func overview(_ page: MediaDetailViewModel) -> Self {
        MediaDetailPanel(
            title: page.item.name,
            subtitle: page.genres,
            text: [page.tagline, page.overview].compactMap { $0 }.joined(separator: "\n\n"),
            facts: [],
            opener: .overview
        )
    }

    static func column(_ column: MediaDetailViewModel.Column) -> Self {
        MediaDetailPanel(title: column.title, subtitle: nil, text: nil, facts: column.facts, opener: .column(column.id))
    }
}

extension MediaDetailPanelView {
    struct Metrics {
        static let width: CGFloat = 1000
        static let padding: CGFloat = 60
        static let spacing: CGFloat = 28
        static let subtitleSpacing: CGFloat = 6
        static let labelSpacing: CGFloat = 4
        static let cornerRadius: CGFloat = 40
        static let dimming = 0.5
    }
}
