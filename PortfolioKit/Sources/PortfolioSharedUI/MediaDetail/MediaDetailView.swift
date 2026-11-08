import PortfolioShared
import SwiftUI

/// An item's full detail page.
public struct MediaDetailView: View {
    let viewModel: MediaDetailViewModel

    public init(viewModel: MediaDetailViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        // FIXME: Show the item's real details, and links to its seasons, cast and related items in place
        // of "Go deeper" (#13).
        VStack(spacing: Metrics.spacing) {
            Text(viewModel.heading)
                .font(.title)
            NavigationLink("Go deeper") {
                MediaDetailView(viewModel: viewModel.deeper())
            }
            Text("Press Menu (or Back) on the remote to go back.")
                .foregroundStyle(.secondary)
        }
        .navigationTitle(viewModel.title)
    }
}

extension MediaDetailView {
    struct Metrics {
        static let spacing: CGFloat = 40
    }
}

#Preview {
    NavigationStack { MediaDetailView(viewModel: MediaDetailViewModel(item: MediaItem.samples[0])) }
}
