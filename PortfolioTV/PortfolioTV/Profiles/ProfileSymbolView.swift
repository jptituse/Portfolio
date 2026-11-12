import SwiftUI

/// A symbol in a circle, standing in for a person's picture on tiles such as "Add Server". It fills
/// whatever frame it's given.
struct ProfileSymbolView: View {
    let systemName: String

    var body: some View {
        Circle()
            .fill(.gray.opacity(Metrics.fillOpacity))
            .overlay {
                Image(systemName: systemName)
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.semibold)
                    .padding(Metrics.symbolPadding)
            }
    }
}

extension ProfileSymbolView {
    struct Metrics {
        static let fillOpacity = 0.4
        static let symbolPadding: CGFloat = 72
    }
}
