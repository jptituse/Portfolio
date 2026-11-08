import SwiftUI

extension MediaCardView {
    public struct Metrics {
        /// A label leaving as its card starts to move. Cards reach their top speed about 70 ms into a
        /// move, so it's gone by then.
        public static var labelFadeOut: Animation { .easeOut(duration: 0.064) }
        /// A label arriving once its card has stopped moving.
        public static var labelFadeIn: Animation { .easeInOut(duration: 0.25) }

        public static let posterCornerRadius: CGFloat = 16
        static let platterCornerRadius: CGFloat = 24

        static let scrimOpacity = 0.85
        static let dimmedOpacity = 0.35
        static let titleLineLimit = 2
        static let titlePadding: CGFloat = 16

        public static let fullScreenDetailsLeadingPadding: CGFloat = 96
        static let platterDetailsLeadingPadding: CGFloat = 64
        /// Space between the bottom of the screen and the details.
        static let detailsBottomMargin: CGFloat = 96
        /// Space the full-screen card leaves below its details for the actions drawn above it.
        static let actionsReservedHeight: CGFloat = 110

        static let lightColor = (saturation: 0.55, brightness: 0.55)
        static let darkColor = (saturation: 0.7, brightness: 0.2)

        static func cornerRadii(for form: MediaCardForm) -> RectangleCornerRadii {
            switch form {
            case .poster:
                RectangleCornerRadii(
                    topLeading: posterCornerRadius,
                    bottomLeading: posterCornerRadius,
                    bottomTrailing: posterCornerRadius,
                    topTrailing: posterCornerRadius
                )
            // Platters run off the bottom of the screen, so only their top corners show.
            case .platter:
                RectangleCornerRadii(topLeading: platterCornerRadius, topTrailing: platterCornerRadius)
            case .fullScreen:
                RectangleCornerRadii()
            }
        }

        static func detailsLeadingPadding(for form: MediaCardForm) -> CGFloat {
            form == .fullScreen ? fullScreenDetailsLeadingPadding : platterDetailsLeadingPadding
        }

        static func detailsBottomPadding(for form: MediaCardForm) -> CGFloat {
            form == .fullScreen ? detailsBottomMargin + actionsReservedHeight : detailsBottomMargin
        }
    }
}
