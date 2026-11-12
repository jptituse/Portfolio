import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// Account and app settings.
struct SettingsView: View {
    @Environment(SessionManager.self) private var sessionManager: SessionManager?
    @State private var isConfirmingRemoval = false

    var body: some View {
        // FIXME: Show the real server, account and playback settings instead of a sample row and this message (#18).
        MediaBrowsingView(groups: [.sample]) {
            HeaderView(
                title: "Settings",
                systemImage: "gearshape",
                message: "Your server, account and playback settings will appear here."
            ) {
                #if DEBUG
                // Temporary, so signing out and starting over can be reached before the real settings
                // view (#18) has them.
                if let sessionManager {
                    HStack {
                        Button("Sign Out (Debug)", role: .destructive) {
                            Task { await sessionManager.signOut() }
                        }
                        Button("Remove All Servers (Debug)", role: .destructive) {
                            isConfirmingRemoval = true
                        }
                    }
                    .confirmationDialog("Remove All Servers?", isPresented: $isConfirmingRemoval) {
                        Button("Remove All Servers", role: .destructive) {
                            Task { try? await sessionManager.removeAllServers() }
                        }
                    } message: {
                        Text("Everyone is signed out and every server is removed from this Apple TV, so the app starts over as if just installed.")
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
