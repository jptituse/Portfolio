import SwiftUI

extension RelatedMediaGroupPosterView {
    struct Metrics {
        /// A movie poster's size. Every poster is this tall, and as wide as its own shape makes it.
        static let posterSize = CGSize(width: 250, height: 375)
        /// A card in a row of items in progress: wide, as a poster becomes once it has widened, but
        /// smaller, so more of them fit.
        static let inProgressCardSize = CGSize(width: 480, height: 270)
        /// Wide enough to show a 16:9 thumbnail at the poster's height. A narrower poster widens to it;
        /// a wider one stays as it is.
        static var extendedPosterWidth: CGFloat { posterSize.height * 16 / 9 }
        /// Long enough for the row to be laid out with that room before a poster grows into it.
        static let makingRoomDelay: Duration = .milliseconds(50)
        static let posterSpacing: CGFloat = 40
        /// Between the row's title and its posters, on top of `verticalPadding`, which leaves room for
        /// a focused poster's lift.
        static let titleSpacing: CGFloat = 4
        static let verticalPadding: CGFloat = 24

        /// How long focus stays on a poster before it widens.
        static let idleDelay: Duration = .seconds(5)
        /// A poster widening or going back to its normal width.
        static var extend: Animation { .smooth(duration: 0.44) }
    }
}
