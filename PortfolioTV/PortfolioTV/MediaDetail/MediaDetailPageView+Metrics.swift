import PortfolioSharedUI
import SwiftUI

extension MediaDetailPageView {
    /// Measured from the TV app's product page at 1080p.
    struct Metrics {
        /// Where the sections' content starts from the screen's edge, as the full-screen card's details.
        static let margin = MediaCardView.Metrics.fullScreenDetailsLeadingPadding
        /// How far the page scrolls before it counts as having left the top.
        static let leftTop: CGFloat = 4
        /// Scrolling between the card and the sections, as the TV app's (about 0.35 s).
        static var scroll: Animation { .smooth(duration: 0.35) }
        /// How long focus rests on an episode's text before its page is built ahead: as long as a
        /// full-screen card waits to build its own, so moving along the row doesn't build one for each.
        static let episodePageBuildDelay: Duration = .milliseconds(600)

        static let sectionsTopPadding: CGFloat = 40
        static let sectionSpacing: CGFloat = 60
        static let titleSpacing: CGFloat = 24
        static let itemSpacing: CGFloat = 40
        static var sectionTitleFont: Font { .headline }
        /// The logo at the top of the sections, as wide as the TV app's.
        static let logoSize = CGSize(width: 560, height: 90)

        /// A person's picture, a circle as the TV app's.
        static let pictureSize = CGSize(width: 260, height: 260)
        /// A similar item's poster, as the TV app's Related row.
        static let posterSize = CGSize(width: 260, height: 390)

        static let tileSpacing: CGFloat = 40
        static let tileHeight: CGFloat = 270
        static let overviewTileWidth: CGFloat = 540
        static let ratingTileWidth: CGFloat = 200
        static let tilePadding: CGFloat = 24
        static let tileTextSpacing: CGFloat = 6
        static let tileCornerRadius: CGFloat = 20
        static let overviewLineLimit = 5
        /// The system's resting platter, and brighter with focus.
        static let tileOpacity = 0.1
        static let focusedTileOpacity = 0.2
        static let focusedScale: CGFloat = 1.05
        static let focusedShadowOpacity = 0.3
        static let focusedShadowRadius: CGFloat = 20
        static let focusedShadowOffset: CGFloat = 10
        static var focusMotion: Animation { .easeOut(duration: 0.2) }

        static let columnSpacing: CGFloat = 24
        /// Around each column's text, inside its focused platter.
        static let factsInset: CGFloat = 20
        static let factsTopPadding: CGFloat = 40
        static let factsBottomPadding: CGFloat = 80
        /// The darker band under the facts, darkening to the bottom.
        static var factsBand: some View {
            LinearGradient(colors: [.black.opacity(0.35), factsBandEnd], startPoint: .top, endPoint: .bottom)
        }
        /// The band's bottom, which carries on below it to the screen's bottom on a short page.
        static var factsBandEnd: Color { .black.opacity(0.85) }

        /// What blurs the backdrop once the card has scrolled away: the system's, as the TV app's.
        static var material: Material { .regularMaterial }
        /// Over the material: lighter at the top, darker below.
        static var wash: some View {
            LinearGradient(colors: [Color(white: 0.5).opacity(0.35), Color(white: 0.08).opacity(0.6)], startPoint: .top, endPoint: .bottom)
        }

        static var panelMotion: Animation { .smooth(duration: 0.3) }
        static var panelTransition: AnyTransition { .opacity.combined(with: .scale(scale: 0.96)) }
    }
}
