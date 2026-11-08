import PortfolioSharedUI
import SwiftUI

/// Continue Watching, Next Up and recently added items.
struct HomeView: View {
    var body: some View {
        // FIXME: Load these shelves from the server instead of showing a sample row and this message (#10).
        MediaBrowsingView(groups: [.sample]) {
            HeaderView(
                title: "Home",
                systemImage: "house",
                message: "Continue Watching, Next Up and recently added items will appear here."
            )
        }
    }
}

#Preview {
    NavigationStack { HomeView() }
}
