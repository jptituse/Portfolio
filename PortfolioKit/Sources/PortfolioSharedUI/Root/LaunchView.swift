import SwiftUI

/// Shown for the moment it takes to restore the saved session at launch.
struct LaunchView: View {
    var body: some View {
        ProgressView()
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    LaunchView()
}
