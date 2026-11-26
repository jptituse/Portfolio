import SwiftUI

/// One of the pictures someone can choose, filling whatever square it's given: its symbol, white, on
/// its color.
public struct ProfilePictureView: View {
    let picture: ProfilePicture

    public init(picture: ProfilePicture) {
        self.picture = picture
    }

    public var body: some View {
        picture.color
            .overlay {
                GeometryReader { geometry in
                    Image(systemName: picture.symbol)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white)
                        .padding(geometry.size.width * Metrics.symbolInset)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .accessibilityLabel(picture.name)
    }
}

extension ProfilePictureView {
    struct Metrics {
        /// How far the symbol sits from the edges, as a share of the picture's width.
        static let symbolInset: CGFloat = 0.25
    }
}

#Preview {
    ProfilePictureView(picture: ProfilePicture.all[0])
        .frame(width: 300, height: 300)
}
