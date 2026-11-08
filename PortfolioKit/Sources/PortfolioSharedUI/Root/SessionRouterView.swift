import SwiftUI

/// Shows the view for a destination. Separate from `RootView` so previews can show any of them.
struct SessionRouterView<Main: View>: View {
    let destination: RootViewModel.Destination
    @ViewBuilder var main: Main

    var body: some View {
        switch destination {
        case .launch: LaunchView()
        case .onboarding: OnboardingView()
        case .main: main
        }
    }
}

#Preview("Signed in") {
    SessionRouterView(destination: .main) { Text("Main UI") }
}

#Preview("Signed out") {
    SessionRouterView(destination: .onboarding) { Text("Main UI") }
}

#Preview("Toggle the session") {
    @Previewable @State var signedIn = false
    VStack {
        Toggle("Signed in", isOn: $signedIn)
        SessionRouterView(destination: signedIn ? .main : .onboarding) { Text("Main UI") }
    }
}
