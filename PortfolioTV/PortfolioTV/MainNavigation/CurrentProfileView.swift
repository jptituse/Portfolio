import PortfolioSharedUI
import SwiftUI

/// The open profile at the top of the sidebar: their picture, name and server. Selecting it goes back
/// to the profile picker to switch profiles, which the line under the name says while it's focused.
struct CurrentProfileView: View {
    let viewModel: CurrentProfileViewModel

    var body: some View {
        if let tile = viewModel.tile {
            Button(action: viewModel.switchProfile) {
                ProfileLabel(tile: tile)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            // Header content sits closer to the edges than the rows, so this lines the focus highlight
            // up with the rows' highlights below, and leaves it room to clear them.
            .padding(.leading, Metrics.leadingInset)
            .padding(.trailing, Metrics.trailingInset)
            .padding(.bottom, Metrics.bottomPadding)
            .accessibilityIdentifier("sidebar.profile")
        }
    }
}

extension CurrentProfileView {
    /// The picture, the name, and under it the server, or "Switch Profile" while focused.
    struct ProfileLabel: View {
        let tile: ProfileTile

        @Environment(\.isFocused) private var isFocused

        var body: some View {
            HStack(spacing: Metrics.spacing) {
                AvatarView(pictureURL: tile.pictureURL, initials: tile.initials)
                    .frame(width: Metrics.avatarSize, height: Metrics.avatarSize)
                VStack(alignment: .leading, spacing: Metrics.textSpacing) {
                    // Primary, not the section header's dimmed style, so it darkens with the focus
                    // highlight like the sidebar's rows.
                    Text(tile.name)
                        .font(.callout)
                        .bold()
                        .foregroundStyle(.primary)
                    Group {
                        if isFocused {
                            Text("Switch Profile")
                        } else if let detail = tile.detail {
                            Text(detail)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(Metrics.textMinimumScale)
            }
        }
    }

    struct Metrics {
        static let spacing: CGFloat = 16
        static let textSpacing: CGFloat = 2
        static let avatarSize: CGFloat = 56
        static let textMinimumScale = 0.8
        /// Measured in 4K screenshots so the focus highlight's edges match the rows' exactly.
        static let leadingInset: CGFloat = 14.5
        static let trailingInset: CGFloat = 13.5
        static let bottomPadding: CGFloat = 32
    }
}
