import PortfolioSharedUI
import SwiftUI

/// Signing in to a server: who's signing in and their password on the leading half, the server's
/// branding on the trailing half. Someone picked from the server's list only types their password.
struct SignInView: View {
    @Bindable var viewModel: SignInViewModel

    var body: some View {
        OnboardingSplitView {
            VStack(spacing: Metrics.spacing) {
                if let tile = viewModel.tile {
                    AvatarView(pictureURL: tile.pictureURL, initials: tile.initials)
                        .frame(width: Metrics.avatarSize, height: Metrics.avatarSize)
                }
                VStack(spacing: Metrics.headerSpacing) {
                    Text(viewModel.title)
                        .font(.title)
                        .bold()
                    Text(viewModel.prompt)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                if viewModel.asksForUsername {
                    TextField("Username", text: $viewModel.username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("onboarding.username")
                }
                if viewModel.asksForPassword {
                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.password)
                        .onSubmit(signIn)
                        .accessibilityIdentifier("onboarding.password")
                }
                Button(action: signIn) {
                    if viewModel.isSigningIn {
                        ProgressView()
                    } else {
                        Text("Sign In")
                    }
                }
                .disabled(!viewModel.canSignIn)
                .accessibilityIdentifier("onboarding.signIn")
                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("onboarding.error")
                }
                if let loginMessage = viewModel.loginMessage {
                    Text(loginMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        } trailing: {
            branding
        }
        .task { await viewModel.loadBranding() }
    }

    /// The server's icon and name, over its own splash image if it has one turned on. The splash fills
    /// the half, keeping its shape, and is blurred and dimmed: a 16:9 image filling a nearly square
    /// half is cropped and enlarged, and the icon and name need to stand out on it.
    private var branding: some View {
        serverIdentity
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if let splashImageURL = viewModel.splashImageURL {
                    RemoteImageView(url: splashImageURL) { image in
                        image
                            .resizable()
                            .scaledToFill()
                            .blur(radius: Metrics.splashBlur, opaque: true)
                            .overlay(.black.opacity(Metrics.splashDimming))
                    } placeholder: {
                        Color.clear
                    }
                }
            }
    }

    private var serverIdentity: some View {
        VStack(spacing: Metrics.identitySpacing) {
            serverIcon
                .frame(height: Metrics.logoHeight)
            VStack(spacing: Metrics.headerSpacing) {
                Text(viewModel.serverName)
                    .font(.title2)
                    .bold()
                Text(viewModel.serverDetails)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, Metrics.identityPadding)
        }
    }

    /// The icon the server's web client offers, or a stand-in for a server without one.
    @ViewBuilder private var serverIcon: some View {
        if let serverIconURL = viewModel.serverIconURL {
            RemoteImageView(url: serverIconURL) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                serverIconStandIn
            }
        } else {
            serverIconStandIn
        }
    }

    private var serverIconStandIn: some View {
        // FIXME: Show Jellyfin's logo once it's an image asset.
        Image(systemName: "server.rack")
            .resizable()
            .scaledToFit()
            .fontWeight(.light)
    }

    private func signIn() {
        Task { await viewModel.signIn() }
    }
}

extension SignInView {
    struct Metrics {
        static let spacing: CGFloat = 32
        static let headerSpacing: CGFloat = 12
        static let avatarSize: CGFloat = 180
        static let identitySpacing: CGFloat = 40
        static let identityPadding: CGFloat = 80
        static let logoHeight: CGFloat = 200
        static let splashBlur: CGFloat = 40
        static let splashDimming = 0.35
    }
}
