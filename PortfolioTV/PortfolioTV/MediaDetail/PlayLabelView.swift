import PortfolioSharedUI
import SwiftUI

/// Play's label: a play icon and "Play", or, where the user left off, a play icon, a bar of how far along
/// they are and the time remaining ("1h 12m"), as the Apple TV app's resume button has it. It reads
/// "Resume" to accessibility, with the time left. Without the item's length, it reads "Resume" on screen too.
struct PlayLabelView: View {
    let card: MediaCardViewModel

    var body: some View {
        if card.canResume, let progress = card.progress, let remaining = card.timeRemainingLabel {
            HStack(spacing: Metrics.spacing) {
                Image(systemName: "play.fill")
                // Hierarchical styles, so the bar darkens with the label as the button takes focus.
                Capsule()
                    .fill(.tertiary)
                    .frame(width: Metrics.barWidth, height: Metrics.barHeight)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.primary)
                            .frame(width: Metrics.barWidth * progress)
                    }
                Text(remaining)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(card.playLabel)
            .accessibilityValue(card.timeLeftLabel ?? remaining)
        } else {
            Label(card.playLabel, systemImage: "play.fill")
        }
    }
}

extension PlayLabelView {
    struct Metrics {
        static let spacing: CGFloat = 16
        static let barWidth: CGFloat = 50
        static let barHeight: CGFloat = 6
    }
}
