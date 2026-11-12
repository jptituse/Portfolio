import PortfolioSharedUI
import SwiftUI

/// Everything before someone is signed in: the profile picker, or the welcome screen on a fresh
/// install, with the steps of adding a server pushed on top. Menu goes back a step.
struct ProfilesView: View {
    @State private var viewModel: ProfilesViewModel

    init(viewModel: ProfilesViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            first
                .navigationDestination(for: ProfilesViewModel.Step.self) { step in
                    view(for: step)
                }
        }
    }

    @ViewBuilder private var first: some View {
        if let picker = viewModel.picker {
            ProfilePickerView(viewModel: picker)
        } else {
            welcome
        }
    }

    @ViewBuilder private func view(for step: ProfilesViewModel.Step) -> some View {
        switch step {
        case .servers(let servers): ServerPickerView(viewModel: servers)
        case .welcome: welcome
        case .server(let server): ServerConnectionView(viewModel: server)
        case .users(let users): UserPickerView(viewModel: users)
        case .signIn(let signIn): SignInView(viewModel: signIn)
        }
    }

    private var welcome: some View {
        #if DEBUG
        WelcomeView(signInOnThisTV: viewModel.addServerByAddress, continueWithSampleSession: viewModel.continueWithSampleSession)
        #else
        WelcomeView(signInOnThisTV: viewModel.addServerByAddress)
        #endif
    }
}
