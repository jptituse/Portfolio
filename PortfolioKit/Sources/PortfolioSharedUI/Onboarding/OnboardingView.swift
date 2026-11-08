import PortfolioShared
import SwiftUI

/// Connecting to a server and signing in.
struct OnboardingView: View {
    @Environment(SessionManager.self) private var sessionManager: SessionManager?

    var body: some View {
        // FIXME: Connect to a server and sign in here instead of showing this message (#7).
        VStack(spacing: Metrics.spacing) {
            ContentUnavailableView(
                "Welcome to Portfolio",
                systemImage: "play.tv",
                description: Text("Connecting to your Jellyfin server will be set up here.")
            )
            #if DEBUG
            // Temporary, so the signed-in app can be explored before onboarding (#7) exists. The
            // sample session points at a server that doesn't exist, so it stays signed in offline.
            if let sessionManager {
                Button("Continue with a Sample Session (Debug)") {
                    try? sessionManager.signIn(.preview)
                }
            }
            #endif
        }
    }
}

extension OnboardingView {
    struct Metrics {
        static let spacing: CGFloat = 40
    }
}

#Preview {
    OnboardingView()
}
