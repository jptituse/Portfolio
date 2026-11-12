import PortfolioSharedUI
import SwiftUI

/// Adding a server: its address and port on the leading half, Portfolio's logo on the trailing half.
/// Continue tries the server, and once it's found, its users come next. Finishing a field doesn't:
/// the port may still be to fill in.
struct ServerConnectionView: View {
    @Bindable var viewModel: ServerConnectionViewModel

    var body: some View {
        OnboardingSplitView {
            VStack(alignment: .leading, spacing: Metrics.spacing) {
                VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                    Text("Your Jellyfin Server")
                        .font(.title)
                        .bold()
                    Text("Enter its address. Add a port only if it doesn't use the usual one.")
                        .foregroundStyle(.secondary)
                }
                TextField("Address", text: $viewModel.address, prompt: Text("192.168.1.10 or jellyfin.example.com"))
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("onboarding.address")
                TextField("Port", text: $viewModel.port, prompt: Text("Port (optional)"))
                    .keyboardType(.numberPad)
                    .accessibilityIdentifier("onboarding.port")
                Button(action: connect) {
                    if viewModel.isConnecting {
                        Label {
                            Text("Looking for Your Server…")
                        } icon: {
                            ProgressView()
                        }
                    } else {
                        Text("Continue")
                    }
                }
                .disabled(!viewModel.canConnect)
                .accessibilityIdentifier("onboarding.continue")
                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("onboarding.error")
                }
            }
        } trailing: {
            VStack(spacing: Metrics.logoSpacing) {
                PortfolioLogoView()
                    .frame(height: Metrics.logoHeight)
                Text("Portfolio")
                    .font(.title2)
                    .bold()
            }
        }
    }

    private func connect() {
        Task { await viewModel.connect() }
    }
}

extension ServerConnectionView {
    struct Metrics {
        static let spacing: CGFloat = 32
        static let headerSpacing: CGFloat = 16
        static let logoSpacing: CGFloat = 32
        static let logoHeight: CGFloat = 240
    }
}
