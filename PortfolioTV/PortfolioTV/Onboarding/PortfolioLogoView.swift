import SwiftUI

/// Portfolio's logo. It fills whatever height it's given.
struct PortfolioLogoView: View {
    var body: some View {
        // FIXME: Show Portfolio's logo once it's an image asset.
        Image(systemName: "play.tv")
            .resizable()
            .scaledToFit()
            .fontWeight(.light)
            .accessibilityLabel("Portfolio")
    }
}

#Preview {
    PortfolioLogoView()
        .frame(height: 200)
}
