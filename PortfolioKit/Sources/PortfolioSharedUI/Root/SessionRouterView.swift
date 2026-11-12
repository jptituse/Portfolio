import SwiftUI

/// Shows the view for a destination. Separate from `RootView` so previews can show any of them.
///
/// Its content comes as closures, so only the destination on show is ever made.
struct SessionRouterView<Profiles: View, Main: View>: View {
    let destination: RootViewModel.Destination
    @ViewBuilder let profiles: () -> Profiles
    @ViewBuilder let main: () -> Main

    var body: some View {
        switch destination {
        case .launch: LaunchView()
        case .profiles: profiles()
        case .main: main()
        }
    }
}

#Preview("Signed in") {
    SessionRouterView(destination: .main) { Text("Profiles") } main: { Text("Main UI") }
}

#Preview("Toggle the session") {
    @Previewable @State var signedIn = false
    VStack {
        Toggle("Signed in", isOn: $signedIn)
        SessionRouterView(destination: signedIn ? .main : .profiles) { Text("Profiles") } main: { Text("Main UI") }
    }
}
