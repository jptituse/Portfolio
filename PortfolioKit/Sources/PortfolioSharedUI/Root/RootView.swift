import PortfolioShared
import SwiftUI

/// The app's top-level view: restores the saved session at launch, then shows onboarding or the main
/// UI depending on whether someone is signed in. Each platform's app supplies its own main UI.
public struct RootView<Main: View>: View {
    @State private var viewModel: RootViewModel
    private let main: Main

    public init(sessionManager: SessionManager, @ViewBuilder main: () -> Main) {
        _viewModel = State(initialValue: RootViewModel(sessionManager: sessionManager))
        self.main = main()
    }

    public var body: some View {
        SessionRouterView(destination: viewModel.destination) { main }
            .environment(viewModel.sessionManager)
            .task { await viewModel.restoreSession() }
    }
}
