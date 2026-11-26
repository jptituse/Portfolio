import PortfolioSharedUI
import SwiftUI

/// Settings, laid out as the Apple TV's own Settings app: the menu's title at the top, its rows on the
/// right, and on the left a large tile for the menu with the description of the row that has focus
/// beneath it.
///
/// Opening a menu pushes it in from the trailing side with SwiftUI's own `.push(from:)` transition, the
/// menu showing leaving toward the leading side, both within the right half; going back runs the other
/// way. The title and the left cross-fade only when the tile changes, and otherwise change in place.
/// Focus goes to the menu's first row, or its choice made, and back to the row a menu opened from.
///
/// It isn't a `NavigationStack`: inside the sidebar's detail column, a stack pushed each menu over the
/// whole column, cross-fading it, and hid the title and the left.
struct SettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @FocusState private var focus: Focus?
    /// The menu on show: the path's last, once the way it moves has been drawn.
    @State private var shown = SettingsMenu.ID.root
    /// Whether the last move went deeper, which decides the side menus come in from.
    @State private var isGoingDeeper = true
    /// The row each menu on the path was left from, for focus to go back to.
    @State private var leftFrom: [SettingsMenu.ID: SettingsMenu.Row.ID] = [:]

    var body: some View {
        VStack(spacing: 0) {
            title
            HStack(alignment: .top, spacing: Metrics.paneSpacing) {
                SettingsDescriptionView(
                    tile: focusedRow.flatMap { openMenu.row($0)?.tile } ?? openMenu.tile,
                    description: viewModel.description(of: focusedRow, in: openMenu.id)
                )
                .frame(width: Metrics.descriptionWidth)
                ZStack(alignment: .top) {
                    SettingsMenuView(menu: viewModel.menu(shown), focus: $focus)
                        .id(shown)
                        .transition(.push(from: isGoingDeeper ? .trailing : .leading))
                }
                .frame(width: Metrics.menuWidth)
                .padding(.top, Metrics.menuTopPadding)
                // Within the right half, with room for the row with focus, which tvOS lifts.
                .padding(Metrics.liftRoom)
                .clipped()
                .padding(-Metrics.liftRoom)
                .focusSection()
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        // As high as the system's title, level with the sidebar's pill.
        .padding(.top, -Metrics.raise)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onExitCommand(perform: viewModel.canGoBack ? { viewModel.back() } : nil)
        .onChange(of: viewModel.path) { old, new in show(from: old, to: new) }
        .alert(
            viewModel.confirmation?.title ?? "",
            isPresented: Binding { viewModel.confirmation != nil } set: { if !$0 { viewModel.confirmation = nil } },
            presenting: viewModel.confirmation
        ) { confirmation in
            ForEach(confirmation.actions) { action in
                Button(action.title, role: action.isDestructive ? .destructive : nil, action: action.perform)
            }
            Button(confirmation.actions.isEmpty ? "OK" : "Cancel", role: .cancel) {}
        } message: { confirmation in
            Text(confirmation.message)
        }
        .alert(
            viewModel.textEdit?.title ?? "",
            isPresented: Binding { viewModel.textEdit != nil } set: { if !$0 { viewModel.textEdit = nil } },
            presenting: viewModel.textEdit
        ) { edit in
            TextField(edit.title, text: $viewModel.textDraft)
            Button("Save", action: edit.save)
            Button("Cancel", role: .cancel) {}
        } message: { edit in
            Text(edit.message)
        }
        .fullScreenCover(isPresented: Binding { viewModel.adding != nil } set: { if !$0 { viewModel.adding = nil } }) {
            if let adding = viewModel.adding {
                ProfilesView(viewModel: adding)
                    // Over Settings, which showed through a cover's own clear background.
                    .presentationBackground(.background)
            }
        }
    }

    /// The open menu, as it is now.
    private var openMenu: SettingsMenu {
        viewModel.menu(viewModel.current)
    }

    /// The row with focus in the open menu.
    private var focusedRow: SettingsMenu.Row.ID? {
        guard let focus, focus.menu == viewModel.current else { return nil }
        return focus.row
    }

    /// The open menu's title, cross-fading with the tile when that changes, and otherwise changing in
    /// place.
    private var title: some View {
        ZStack {
            Text(openMenu.title)
                .font(Metrics.titleFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .id(openMenu.tile)
                .transition(.opacity)
                .accessibilityAddTraits(.isHeader)
        }
        .animation(SettingsDescriptionView.Metrics.crossFade, value: openMenu.tile)
        .frame(height: Metrics.titleHeight)
    }

    /// Shows the menu the path ends with, moving in from the side it's on. The way it moves is drawn
    /// first: the menu leaving moves as it was last drawn.
    private func show(from old: [SettingsMenu.ID], to new: [SettingsMenu.ID]) {
        let deeper = new.count > old.count
        if deeper, let focus { leftFrom[focus.menu] = focus.row }
        isGoingDeeper = deeper
        let next = new.last ?? .root
        Task {
            withAnimation(Metrics.motion) {
                shown = next
            } completion: {
                let target = deeper ? viewModel.focusTarget(in: next) : leftFrom[next] ?? viewModel.focusTarget(in: next)
                focus = target.map { Focus(menu: next, row: $0) }
            }
        }
    }
}

extension SettingsView {
    /// Which row has focus, in which menu: menus on the stack can have rows of the same name.
    struct Focus: Hashable {
        let menu: SettingsMenu.ID
        let row: SettingsMenu.Row.ID
    }

    /// Measured from the system's Settings app on an Apple TV 4K: its menus' rows are 782 points wide,
    /// 80 from the screen's trailing edge, and the tile is centered in the rest.
    struct Metrics {
        static let titleFont = Font.title2.weight(.bold)
        static let titleHeight: CGFloat = 100
        /// How far above the safe area the title sits.
        static let raise: CGFloat = 80
        /// Below the title, down to the first row.
        static let menuTopPadding: CGFloat = 48
        static let descriptionWidth: CGFloat = 890
        static let menuWidth: CGFloat = 790
        static let paneSpacing: CGFloat = 80
        static let motion = Animation.smooth(duration: 0.4)
        /// Room past the menus' edges for the row with focus, which tvOS lifts and shadows.
        static let liftRoom: CGFloat = 50
    }
}

#if DEBUG
#Preview {
    SettingsView(viewModel: .preview())
}
#endif
