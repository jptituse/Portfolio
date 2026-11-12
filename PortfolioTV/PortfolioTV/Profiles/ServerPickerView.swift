import PortfolioSharedUI
import SwiftUI

/// Someone who isn't on the profile picker picks their server: a tile for each server added to this
/// device, with its icon and address, and one to add another.
struct ServerPickerView: View {
    let viewModel: ServerPickerViewModel

    var body: some View {
        VStack(spacing: Metrics.spacing) {
            Text(viewModel.title)
                .font(.title)
                .bold()
            ProfileTilesView {
                ForEach(viewModel.tiles) { tile in
                    ProfileTileView(name: tile.name, detail: tile.detail) {
                        viewModel.pick(tile.id)
                    } picture: {
                        ServerIconView(iconURL: tile.pictureURL)
                    }
                }
                ProfileTileView(name: "Add Server") {
                    viewModel.addServer()
                } picture: {
                    ProfileSymbolView(systemName: "plus")
                }
            }
        }
        .task { await viewModel.loadIcons() }
    }
}

extension ServerPickerView {
    struct Metrics {
        static let spacing: CGFloat = 40
    }
}
