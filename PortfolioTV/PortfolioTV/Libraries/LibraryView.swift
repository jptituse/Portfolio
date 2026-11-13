import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// A library: its sidebar items on the left (Recently Added, all its items, and its genres) beside a
/// grid of the chosen sidebar item's posters. The grid follows focus on the sidebar items and loads
/// more as it's scrolled. Selecting a poster grows it straight into the item's full-screen card, and
/// Back shrinks it back onto the poster (`MediaCardExpansionViewModel`). Back from a poster goes to
/// the sidebar item showing; Back from the sidebar items brings in the sidebar, as usual. The library
/// loads again each time it's shown.
struct LibraryView: View {
    let viewModel: LibraryViewModel
    /// Whether this library is the section on screen. Sections stay alive while another one shows.
    let isShowing: Bool

    @Environment(\.displayScale) private var displayScale
    /// The screen's safe area, which the grid runs past to the edges.
    @State private var safeArea = EdgeInsets()
    @FocusState private var focus: LibraryFocus?
    @State private var expansion = MediaCardExpansionViewModel()

    var body: some View {
        ZStack {
            HStack(alignment: .top, spacing: Metrics.spacing) {
                LibrarySidebarView(viewModel: viewModel, focus: $focus)
                    .frame(width: Metrics.sidebarWidth)
                    .padding(.top, Metrics.topPadding)
                LibraryGridView(
                    viewModel: viewModel,
                    expansion: expansion,
                    focus: $focus,
                    margins: EdgeInsets(top: safeArea.top + Metrics.topPadding, leading: 0, bottom: safeArea.bottom, trailing: 0)
                )
            }
            .disabled(expansion.holdsFocus)

            GeometryReader { proxy in
                if let card = expansion.card {
                    MediaCardExpansionView(
                        viewModel: expansion,
                        card: card,
                        globalFrame: proxy.frame(in: .global),
                        focus: $focus,
                        actionsFocus: .detail(card.item.id)
                    )
                    // The card appears exactly on top of its poster, so it must not fade in.
                    .transition(.identity)
                    .onAppear {
                        expansion.grow { [focus = $focus] in
                            // Once the actions are on screen.
                            Task { @MainActor in focus.wrappedValue = .detail(card.item.id) }
                        }
                    }
                }
            }
            .ignoresSafeArea()
        }
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { safeArea = $0 }
        // The detail card's artwork fills the screen, so it's fetched at the screen's size.
        .onGeometryChange(for: CGSize.self, of: \.screenSize) { screen in
            viewModel.setArtworkSizes(
                poster: LibraryGridView.Metrics.posterSize(for: viewModel.posterAspectRatio),
                screen: screen,
                logo: MediaCardView.Metrics.detailsLogoSize,
                scale: displayScale
            )
        }
        .onChange(of: focus) { _, focus in
            switch focus {
            case .sidebarItem(let sidebarItem):
                viewModel.sidebarItemFocused(sidebarItem)
            case .poster(let id):
                if let item = viewModel.items.first(where: { $0.id == id }) { viewModel.posterFocused(item) }
            case .detail, nil:
                break
            }
        }
        .onExitCommand(perform: exitAction)
        .task(id: isShowing) {
            if isShowing { await viewModel.load() }
        }
    }
}

extension LibraryView {
    /// What Back does: shrinks an expanded card back onto its poster, and from a poster goes to the
    /// sidebar item showing. Otherwise it does what it always does.
    private var exitAction: (() -> Void)? {
        if let item = expansion.item {
            return { [focus = $focus] in
                expansion.collapse { focus.wrappedValue = .poster(item) }
            }
        }
        if case .poster = focus {
            return { focus = .sidebarItem(viewModel.chosenSidebarItem) }
        }
        return nil
    }

    struct Metrics {
        static let sidebarWidth: CGFloat = 400
        static let spacing: CGFloat = 60
        static let topPadding: CGFloat = 40
    }
}
