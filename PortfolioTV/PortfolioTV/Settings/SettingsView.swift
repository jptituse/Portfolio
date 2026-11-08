import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// Account and app settings.
struct SettingsView: View {
    @Environment(SessionManager.self) private var sessionManager: SessionManager?

    var body: some View {
        // FIXME: Show the real server, account and playback settings instead of a sample row and this message (#18).
        MediaBrowsingView(groups: [.sample]) {
            HeaderView(
                title: "Settings",
                systemImage: "gearshape",
                message: "Your server, account and playback settings will appear here."
            ) {
                #if DEBUG
                // Temporary, so the signed-out state can be reached before the real settings view
                // (#18) adds sign-out.
                if let sessionManager {
                    Button("Sign Out (Debug)", role: .destructive) {
                        Task { await sessionManager.signOut() }
                    }
                }
                #endif
            }
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
