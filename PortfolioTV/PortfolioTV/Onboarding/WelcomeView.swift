import SwiftUI

/// The first screen of a fresh install, and of adding another server: sign in on this TV with the
/// server's address, or with a phone.
struct WelcomeView: View {
    let signInOnThisTV: () -> Void
    #if DEBUG
    let continueWithSampleSession: () -> Void
    #endif

    var body: some View {
        VStack(spacing: Metrics.spacing) {
            PortfolioLogoView()
                .frame(height: Metrics.logoHeight)
            VStack(spacing: Metrics.textSpacing) {
                Text("Welcome to Portfolio")
                    .font(.title)
                    .bold()
                Text("Watch everything on your Jellyfin server.")
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: Metrics.buttonSpacing) {
                Button("Sign In on This TV", action: signInOnThisTV)
                // FIXME: Sign in with Quick Connect: show a code here to approve from the Jellyfin app or
                // website on a phone (#8).
                Button("Use Your Phone") {}
                    .disabled(true)
                #if DEBUG
                // Temporary, so the signed-in app can be explored without a server.
                Button("Continue with a Sample Session (Debug)", action: continueWithSampleSession)
                #endif
            }
        }
    }
}

extension WelcomeView {
    struct Metrics {
        static let spacing: CGFloat = 56
        static let textSpacing: CGFloat = 16
        static let buttonSpacing: CGFloat = 24
        static let logoHeight: CGFloat = 180
    }
}
