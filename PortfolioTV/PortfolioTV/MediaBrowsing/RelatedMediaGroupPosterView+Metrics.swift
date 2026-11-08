import SwiftUI

extension RelatedMediaGroupPosterView {
    struct Metrics {
        static let posterSize = CGSize(width: 250, height: 375)
        /// Wide enough to show a 16:9 thumbnail at the poster's height.
        static let extendedPosterWidth: CGFloat = 667
        static var extensionRoom: CGFloat { extendedPosterWidth - posterSize.width }
        /// Long enough for the row to be laid out with that room before a poster grows into it.
        static let makingRoomDelay: Duration = .milliseconds(50)
        static let posterSpacing: CGFloat = 40
        static let titleSpacing: CGFloat = 24
        static let verticalPadding: CGFloat = 24

        /// How long focus stays on a poster before it widens.
        static let idleDelay: Duration = .seconds(5)
        /// A poster widening or going back to its normal width.
        static var extend: Animation { .smooth(duration: 0.44) }
    }
}
