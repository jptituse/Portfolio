import PortfolioSharedUI
import SwiftUI

/// Search across the server.
struct SearchView: View {
    var body: some View {
        // FIXME: Search the server and show the results instead of a sample row and this message.
        MediaBrowsingView(groups: [.sample]) {
            HeaderView(
                title: "Search",
                systemImage: "magnifyingglass",
                message: "Search for movies, shows, episodes and people."
            )
        }
    }
}

#Preview {
    NavigationStack { SearchView() }
}
