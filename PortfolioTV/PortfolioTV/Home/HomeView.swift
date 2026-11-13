import PortfolioSharedUI
import SwiftUI

/// The open profile's Home: what was added to their libraries most recently. It loads again each time
/// it's shown.
struct HomeView: View {
    let viewModel: HomeViewModel
    /// Whether Home is the section on screen. Sections stay alive while another one shows.
    let isShowing: Bool

    var body: some View {
        MediaBrowsingView(groups: viewModel.groups, images: viewModel.images) {
            HeaderView(title: "Home", systemImage: "house", message: "What's new in your libraries.") {
                if viewModel.isLoading {
                    ProgressView()
                } else if let message = viewModel.message {
                    Text(message)
                        .foregroundStyle(.secondary)
                    if viewModel.canRetry {
                        Button("Try Again") {
                            Task { await viewModel.load() }
                        }
                        .accessibilityIdentifier("home.retry")
                    }
                }
            }
        }
        // The browsing view starts over with the rows once they've loaded, or when they change.
        .id(viewModel.groups)
        .task(id: isShowing) {
            if isShowing { await viewModel.load() }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { HomeView(viewModel: .preview(), isShowing: true) }
}
#endif
