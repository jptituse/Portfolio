import SwiftUI

/// A server's icon in a circle, for its tile in a picker: the icon its web client offers, or a stand-in
/// until it loads or for a server without one. It fills whatever frame it's given.
struct ServerIconView: View {
    let iconURL: URL?

    var body: some View {
        Circle()
            .fill(.gray.opacity(Metrics.fillOpacity))
            .overlay {
                // FIXME: Load the icon through the shared image pipeline, with caching, once it exists (#9).
                AsyncImage(url: iconURL) { image in
                    image
                        .resizable()
                        .scaledToFit()
                } placeholder: {
                    Image(systemName: "server.rack")
                        .resizable()
                        .scaledToFit()
                        .fontWeight(.light)
                }
                .padding(Metrics.iconPadding)
            }
    }
}

extension ServerIconView {
    struct Metrics {
        static let fillOpacity = 0.4
        static let iconPadding: CGFloat = 56
    }
}
