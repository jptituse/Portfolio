import PortfolioSharedUI
import SwiftUI

/// Who's signing in to a server that was just found: a tile for each person it lists, and one for
/// someone else.
struct UserPickerView: View {
    let viewModel: UserPickerViewModel

    var body: some View {
        VStack(spacing: Metrics.spacing) {
            Text(viewModel.title)
                .font(.title)
                .bold()
            ProfileTilesView {
                ForEach(viewModel.tiles) { tile in
                    ProfileTileView(name: tile.name) {
                        viewModel.pick(tile.id)
                    } picture: {
                        AvatarView(pictureURL: tile.pictureURL, initials: tile.initials)
                    }
                }
                ProfileTileView(name: "Someone Else") {
                    viewModel.pickSomeoneElse()
                } picture: {
                    ProfileSymbolView(systemName: "person.fill.questionmark")
                }
            }
        }
    }
}

extension UserPickerView {
    struct Metrics {
        static let spacing: CGFloat = 40
    }
}
