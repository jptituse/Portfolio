import PortfolioSharedUI
import SwiftUI

/// The user's libraries, such as Movies and Shows.
struct LibrariesView: View {
    var body: some View {
        // FIXME: Load the user's libraries from the server instead of showing a sample row and this message (#11).
        MediaBrowsingView(groups: [.sample]) {
            HeaderView(
                title: "Libraries",
                systemImage: "rectangle.stack",
                message: "Your movie, show and other libraries will appear here."
            )
        }
    }
}

#Preview {
    NavigationStack { LibrariesView() }
}
