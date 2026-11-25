import PortfolioSharedPlaybackEngine
import PortfolioSharedUI
import SwiftUI

/// The player's menu buttons, round glass buttons beside its title as the system player's are:
/// Subtitles while there are any, Audio and More. Each opens its menu (`PlayerMenuView`) above it, its
/// trailing edge on the button's, growing out of the button and shrinking back into it.
///
/// The button keeps focus until focus moves into the menu, then is gray while the menu is open. The
/// buttons can't take focus meanwhile, so it stays in the menu.
struct PlayerMenusView: View {
    let viewModel: PlayerViewModel
    var focus: FocusState<PlayerView.Focus?>.Binding
    /// How subtitles would look with the caption style that has focus in a menu, if one has.
    @Binding var previewStyle: CaptionStyle?

    /// The menu open, and once it's closed, until it has shrunk back into its button.
    @State private var shown: Shown?
    /// How many times each menu has opened, so each opening is a new menu, even over one still closing.
    @State private var openings: [PlayerMenu.ID: Int] = [:]

    var body: some View {
        HStack(spacing: Metrics.spacing) {
            ForEach(viewModel.menus) { menu in
                let isOpen = viewModel.openMenuRoot == menu.id
                let closingID: PlayerMenu.ID? = if !isOpen, let shown, shown.root == menu.id { shown.menu } else { nil }
                // Until focus moves into the menu.
                let holdsFocus = focus.wrappedValue == .menu(menu.id)
                let look: MenuButtonStyle.Look = viewModel.openMenuRoot == nil || (isOpen && holdsFocus) ? .usual : isOpen ? .open : .behindMenu
                // The menu hangs off a stack around the button, not the button: changing from the
                // system's button to one drawn as it looks made a new button, and a new menu with it,
                // which grew all over again.
                ZStack {
                    Button {
                        // Again before focus has moved into it, it stays as it is.
                        guard !isOpen else { return }
                        openings[menu.id, default: 0] += 1
                        viewModel.openMenu(menu.id)
                    } label: {
                        Label(menu.title, systemImage: Self.symbol(for: menu.id))
                            // White behind a menu, where it can't take focus, which would dim it.
                            .foregroundStyle(look == .behindMenu ? AnyShapeStyle(.white) : AnyShapeStyle(.foreground))
                    }
                    .buttonStyle(MenuButtonStyle(look: look))
                    .animation(Metrics.lookChange, value: look)
                    .disabled(viewModel.openMenuRoot != nil && !(isOpen && holdsFocus))
                    .focused(focus, equals: .menu(menu.id))
                    .accessibilityIdentifier("player.\(menu.id)")
                }
                .overlay(alignment: .bottomTrailing) {
                    // Above the button, on its trailing edge.
                    if let visible = isOpen ? viewModel.openMenu : closingID.flatMap(viewModel.menu) {
                        PlayerMenuView(
                            menu: visible,
                            depth: viewModel.openMenuDepth,
                            focusTarget: viewModel.menuFocus,
                            isClosing: !isOpen,
                            onClosed: {
                                if shown?.root == menu.id, viewModel.openMenuRoot != menu.id { shown = nil }
                            },
                            onChoose: { viewModel.choose($0) },
                            previewStyle: $previewStyle
                        )
                        .fixedSize()
                        .id(openings[menu.id, default: 0])
                        .transition(.identity)
                        .padding(.bottom, Metrics.buttonSize + Metrics.menuSpacing)
                    }
                }
                // Over the buttons beside it.
                .zIndex(isOpen || closingID != nil ? 1 : 0)
            }
        }
        .labelStyle(.iconOnly)
        .buttonBorderShape(.circle)
        // Back to its button once its menu closes, once that can take focus again. Followed here, not by
        // the player, which would be drawn again as each menu opens and closes.
        .onChange(of: viewModel.openMenuRoot) { closed, open in
            if open == nil, let closed { Task { focus.wrappedValue = .menu(closed) } }
        }
        // Kept through the update that closes it, so the same menu shrinks away.
        .onChange(of: Shown(root: viewModel.openMenuRoot, menu: viewModel.openMenu?.id), initial: true) { _, now in
            if now.root != nil { shown = now }
        }
    }

    /// The symbol on a menu's button, as the system player's.
    private static func symbol(for menu: PlayerMenu.ID) -> String {
        switch menu {
        case "subtitles": "captions.bubble"
        case "audio": "waveform"
        default: "ellipsis"
        }
    }
}

extension PlayerMenusView {
    /// Which menu's button opened what shows, and which menu or submenu that is.
    struct Shown: Equatable {
        let root: PlayerMenu.ID?
        let menu: PlayerMenu.ID?
    }

    /// The system's glass button, gray while its menu is open, as the system player's.
    ///
    /// It's the same glass button whatever the look. Drawn as glass of its own behind a menu, a new glass
    /// view faded in over the button's as each menu opened, and on an Apple TV the buttons stuttered and
    /// their glass flickered dark and light as it adapted to the picture from scratch. The gray covers
    /// the glass rather than taking its place.
    struct MenuButtonStyle: PrimitiveButtonStyle {
        enum Look {
            case usual, open, behindMenu
        }

        let look: Look

        func makeBody(configuration: Configuration) -> some View {
            GlassButtonStyle().makeBody(configuration: configuration)
                .overlay {
                    Circle()
                        .fill(Metrics.openFill)
                        .overlay { configuration.label.font(Metrics.iconFont).foregroundStyle(.white) }
                        .frame(width: Metrics.buttonSize + 2 * Metrics.openOverhang, height: Metrics.buttonSize + 2 * Metrics.openOverhang)
                        .opacity(look == .open ? 1 : 0)
                        .accessibilityHidden(true)
                }
        }
    }

    /// Measured from the system player, whose buttons are 90 points apart. The system's glass buttons
    /// are 63 points across, a little smaller than the system player's. The menus' own motion is
    /// `PlayerMenuView`'s.
    struct Metrics {
        static let spacing: CGFloat = 27
        static let buttonSize: CGFloat = 63
        /// Between a menu and the buttons under it.
        static let menuSpacing: CGFloat = 22
        /// A button whose menu is open, reaching over the glass's rim, which shows 2 points past it.
        static let openFill = Color(white: 0.43)
        static let openOverhang: CGFloat = 2
        static var iconFont: Font { .body }
        /// A button going gray as focus moves into its menu.
        static var lookChange: Animation { .easeOut(duration: 0.15) }
    }
}
