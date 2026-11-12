import PortfolioSharedUI
import SwiftUI

/// "Who's watching?": a tile for everyone on the servers added to this device, and one for someone
/// else. It starts on the profile opened last. Picking a signed-in profile opens its Home; anyone else
/// signs in first. Someone else picks their server next, or adds it.
struct ProfilePickerView: View {
    let viewModel: ProfilePickerViewModel

    @FocusState private var focusedTile: ProfileTile.ID?

    var body: some View {
        VStack(spacing: Metrics.spacing) {
            Text("Who's Watching?")
                .font(.title)
                .bold()
            ProfileTilesView {
                ForEach(viewModel.tiles) { tile in
                    ProfileTileView(name: tile.name, detail: tile.detail, isBusy: viewModel.isOpening(tile.id)) {
                        Task { await viewModel.open(tile.id) }
                    } picture: {
                        AvatarView(pictureURL: tile.pictureURL, initials: tile.initials)
                    }
                    .focused($focusedTile, equals: tile.id)
                }
                ProfileTileView(name: "Someone Else") {
                    viewModel.someoneElse()
                } picture: {
                    ProfileSymbolView(systemName: "person.fill.questionmark")
                }
            }
        }
        .defaultFocus($focusedTile, viewModel.initialFocus)
        .task { await viewModel.refresh() }
    }
}

extension ProfilePickerView {
    struct Metrics {
        static let spacing: CGFloat = 40
    }
}
