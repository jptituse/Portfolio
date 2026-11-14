import SwiftUI

/// How far along an item is, as Continue Watching shows it on a card: a play icon, a bar of how much
/// has been watched (left out if nothing has), the episode ("S1E5", left out for a movie), and the time
/// left.
struct MediaProgressIndicatorView: View {
    let progress: Double?
    let episodeLabel: String?
    let timeLeftLabel: String?

    var body: some View {
        HStack(spacing: Metrics.spacing) {
            Image(systemName: "play.fill")
            if let progress {
                Capsule()
                    .fill(.white.opacity(Metrics.trackOpacity))
                    .frame(width: Metrics.barWidth, height: Metrics.barHeight)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.white)
                            .frame(width: Metrics.barWidth * progress)
                    }
            }
            if let episodeLabel {
                Text(episodeLabel)
            }
            if let timeLeftLabel {
                Text(timeLeftLabel)
            }
        }
        .font(.caption2)
        .fontWeight(.semibold)
        .foregroundStyle(.white)
        .lineLimit(1)
        .shadow(color: .black.opacity(Metrics.shadowOpacity), radius: Metrics.shadowRadius)
    }
}

extension MediaProgressIndicatorView {
    struct Metrics {
        static let spacing: CGFloat = 10
        static let barWidth: CGFloat = 64
        static let barHeight: CGFloat = 6
        static let trackOpacity = 0.35
        static let shadowOpacity = 0.6
        static let shadowRadius: CGFloat = 4
    }
}

#Preview {
    MediaProgressIndicatorView(progress: 0.4, episodeLabel: "S1E5", timeLeftLabel: "23m left")
        .padding()
        .background(.gray)
}
