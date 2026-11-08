import PortfolioShared
import SwiftUI

/// The signed-in user at the top of the sidebar, like the profile in the TV app.
struct SidebarProfileHeaderView: View {
    @Environment(SessionManager.self) private var sessionManager: SessionManager?

    var body: some View {
        Group {
            if let user = sessionManager?.state.session?.user {
                Label(user.name, systemImage: "person.crop.circle.fill")
            } else {
                Label("Portfolio", systemImage: "play.tv")
            }
        }
        .font(.headline)
        .lineLimit(Metrics.lineLimit)
    }
}

extension SidebarProfileHeaderView {
    struct Metrics {
        static let lineLimit = 1
    }
}
