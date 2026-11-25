import PortfolioSharedPlaybackEngine
import PortfolioSharedUI
import SwiftUI

/// One of the player's menus, open above its button, drawn as the system player draws its own: a glass
/// panel of sections, each under a gray header if it has one, divided by lines. A choice or a toggle on is
/// checked, and a submenu shows what's chosen in it under its title. The item with focus is a white
/// capsule. It's as wide as the TV app's, or wider for long names, up to a point, and scrolls where it's
/// taller than fits.
///
/// A submenu takes its menu's place with SwiftUI's own `.push(from:)` transition: it pushes in from the
/// trailing side as the menu leaves toward the leading side, while the panel springs to its size about
/// its bottom trailing corner, as the system's does (AVKit's, recorded at 60 fps). Going back runs the
/// other way.
///
/// It grows out of its button as the system's does: from nothing to a little past its size and back, on
/// a slightly bouncy spring, fading in as it grows. Once `isClosing`, it shrinks back toward the button,
/// gone in 0.14 s, then calls `onClosed`.
///
/// Focus lands in a submenu on what the view model names once the push has finished, as the system's
/// does: SwiftUI doesn't let focus onto a view whose insertion transition is still running, and moved at
/// the start, focus stalls a motion's first frames on an Apple TV. As the menu opens, focus moves in once
/// the panel has nearly grown. Growing and shrinking are the panel's own motion, not a transition: a menu
/// removed with one only faded, late.
///
/// While a caption style has focus, `previewStyle` is how subtitles would look with it.
struct PlayerMenuView: View {
    let menu: PlayerMenu
    /// How deep `menu` is: 1 for a menu, 2 for a submenu opened from it.
    let depth: Int
    /// Where focus goes as the menu, or a submenu, opens or comes back.
    let focusTarget: PlayerMenu.Item.ID?
    let isClosing: Bool
    let onClosed: () -> Void
    let onChoose: (PlayerMenu.Item) -> Void
    @Binding var previewStyle: CaptionStyle?

    /// The menu in the panel. Each that takes another's place is a new one, so it pushes in.
    @State private var shown: Layer
    @State private var nextLayerID = 1
    /// Whether the last menu to arrive was deeper, which decides the side it pushes in from. Drawn before
    /// the menu changes: a view leaving moves as it was last drawn.
    @State private var isGoingDeeper = true
    /// How many times a menu has taken another's place, so that only the last one's end moves focus.
    @State private var moves = 0
    /// How far it has grown out of its button.
    @State private var growth = 0.0
    /// The menu focus has been put in since it arrived. Until then none of its focus shows: tvOS moves
    /// focus into an arriving menu by itself, onto its first item, before it's put where it belongs.
    @State private var settledLayer: Int?
    /// Where focus is being put, which shows once it's there.
    @State private var focusing: FocusedItem?
    @FocusState private var focusedItem: FocusedItem?

    init(
        menu: PlayerMenu,
        depth: Int,
        focusTarget: PlayerMenu.Item.ID?,
        isClosing: Bool,
        onClosed: @escaping () -> Void,
        onChoose: @escaping (PlayerMenu.Item) -> Void,
        previewStyle: Binding<CaptionStyle?>
    ) {
        self.menu = menu
        self.depth = depth
        self.focusTarget = focusTarget
        self.isClosing = isClosing
        self.onClosed = onClosed
        self.onChoose = onChoose
        _previewStyle = previewStyle
        _shown = State(initialValue: Layer(id: 0, menu: menu, depth: depth, scrollTarget: focusTarget))
    }

    var body: some View {
        Panel(current: shown.id) {
            LayerView(
                // The open menu as it is now.
                menu: shown.menu.id == menu.id ? menu : shown.menu,
                layer: shown.id,
                showsFocus: shown.id == settledLayer,
                scrollTarget: shown.scrollTarget,
                focusedItem: $focusedItem,
                onChoose: onChoose
            )
            .id(shown.id)
            .layoutValue(key: Panel.LayerKey.self, value: shown.id)
            .transition(.push(from: isGoingDeeper ? .trailing : .leading))
        }
        .clipShape(.rect(cornerRadius: Metrics.cornerRadius))
        .glassEffect(.regular, in: .rect(cornerRadius: Metrics.cornerRadius))
        .focusSection()
        .disabled(isClosing)
        // Grown, opening and closing look the same, so it can change from one to the other.
        .modifier(isClosing
            ? Growth(progress: growth, smallest: Metrics.closedScale, shows: Metrics.showsClosing, faintest: 0)
            : Growth(progress: growth, smallest: Metrics.openingScale, shows: Metrics.showsOpening))
        .onChange(of: isClosing) { _, closing in
            guard closing else { return }
            Task {
                // Once the frames closing costs are drawn, as for every motion here: see `arrive(_:)`.
                try? await Task.sleep(for: Metrics.buildPause)
                withAnimation(Metrics.closing, completionCriteria: .logicallyComplete) {
                    growth = 0
                } completion: {
                    onClosed()
                }
            }
        }
        .task {
            // Built first, grown once that's done: see `arrive(_:)`.
            try? await Task.sleep(for: Metrics.buildPause)
            withAnimation(Metrics.opening) { growth = 1 }
            try? await Task.sleep(for: Metrics.focusDelay)
            await settle(after: 0)
        }
        .onChange(of: menu.id) { _, _ in arrive(menu) }
        .onChange(of: focusedItem, initial: true) { _, focused in
            if let focused, focused == focusing { showFocus() }
            updatePreview()
        }
        .onChange(of: settledLayer) { updatePreview() }
        .onDisappear { previewStyle = nil }
    }

    /// `next` takes the place of the menu showing, pushing in from the side it's deeper on. Which side,
    /// and the leaving menu's focus hidden, are drawn first: a view leaving moves as it was last drawn.
    ///
    /// The push waits `buildPause` to start (`Animation.delay`). Every change to the menus kept an Apple
    /// TV's main thread busy for 50–60 ms (Instruments' Animation Hitches, on an Apple TV 4K), and a motion
    /// started with it skipped those frames: a push looked like a crossfade. Started after, it waits a
    /// moment, as the system's does, then runs whole at 60 fps. Focus lands `settleDelay` after it starts.
    private func arrive(_ next: PlayerMenu) {
        moves += 1
        let move = moves
        isGoingDeeper = depth > shown.depth
        settledLayer = nil
        focusing = nil
        let arriving = Layer(id: nextLayerID, menu: next, depth: depth, scrollTarget: focusTarget)
        nextLayerID += 1
        Task {
            guard move == moves else { return }
            withAnimation(Metrics.push.delay(Metrics.buildPause / .seconds(1))) {
                shown = arriving
            }
            try? await Task.sleep(for: Metrics.buildPause + Metrics.settleDelay)
            await settle(after: move)
        }
    }

    /// Focus on the item the view model names in the open menu, else its first, unless a menu has taken
    /// another's place since `move`. Asked again until it's there, and shown once it is, or wherever it is
    /// if it never gets there.
    private func settle(after move: Int) async {
        for _ in 0..<Metrics.focusAttempts {
            guard move == moves, let item = focusTarget ?? menu.sections.first?.items.first?.id else { return }
            let target = FocusedItem(layer: shown.id, item: item)
            // tvOS may have put it there already, as on a menu's first item.
            if focusedItem == target { break }
            focusing = target
            focusedItem = target
            try? await Task.sleep(for: Metrics.focusRetry)
            if focusedItem == target { break }
        }
        guard move == moves else { return }
        showFocus()
    }

    /// Shows the open menu's focus, wherever it is.
    private func showFocus() {
        focusing = nil
        settledLayer = shown.id
    }

    /// While a caption style has focus, once focus shows, how subtitles would look with it.
    private func updatePreview() {
        previewStyle = focusedItem.flatMap { focused in
            guard focused.layer == settledLayer, focused.layer == shown.id else { return nil }
            return menu.sections.flatMap(\.items).first { $0.id == focused.item }?.captionStyle
        }
    }

}

extension PlayerMenuView {
    /// A menu in the panel.
    struct Layer: Identifiable {
        let id: Int
        let menu: PlayerMenu
        let depth: Int
        /// The item to scroll to as it arrives, so the list doesn't scroll as focus lands.
        var scrollTarget: PlayerMenu.Item.ID?
    }

    /// Which item has focus, in which of the panel's menus: a menu leaving and the one arriving can have
    /// items of the same name.
    struct FocusedItem: Hashable {
        let layer: Int
        let item: PlayerMenu.Item.ID
    }

    /// A menu's sections, scrolling where they're taller than fits.
    struct LayerView: View {
        let menu: PlayerMenu
        let layer: Int
        /// Whether its focus shows: only the open menu's, once focus has been put in it.
        let showsFocus: Bool
        let scrollTarget: PlayerMenu.Item.ID?
        var focusedItem: FocusState<FocusedItem?>.Binding
        let onChoose: (PlayerMenu.Item) -> Void

        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    Stack(minWidth: Metrics.width, maxWidth: Metrics.maxWidth) {
                        ForEach(Array(menu.sections.enumerated()), id: \.element.id) { index, section in
                            if index > 0 {
                                Rectangle()
                                    .fill(.white.opacity(Metrics.separatorOpacity))
                                    .frame(height: Metrics.separatorHeight)
                                    .padding(.top, Metrics.separatorSpacing)
                                    .padding(.horizontal, Metrics.headerInset)
                            }
                            if let header = section.header {
                                Text(header)
                                    .font(Metrics.headerFont)
                                    .foregroundStyle(.white.opacity(Metrics.secondaryOpacity))
                                    .lineLimit(1)
                                    .padding(.horizontal, Metrics.headerInset)
                                    .frame(height: Metrics.headerHeight)
                                    .padding(.top, Metrics.headerTopSpacing)
                            } else if index == 0 {
                                Spacer().frame(height: Metrics.verticalPadding)
                            }
                            ForEach(section.items) { item in
                                Button { onChoose(item) } label: {
                                    ItemLabel(item: item)
                                }
                                .buttonStyle(ItemButtonStyle(showsFocus: showsFocus))
                                .focused(focusedItem, equals: FocusedItem(layer: layer, item: item.id))
                                .id(item.id)
                            }
                        }
                    }
                    .padding(.bottom, Metrics.verticalPadding)
                }
                .frame(maxHeight: Metrics.maxHeight)
                .onAppear {
                    // Only as far as shows it, at once rather than in the motion arriving.
                    guard let scrollTarget else { return }
                    var still = Transaction()
                    still.disablesAnimations = true
                    withTransaction(still) { proxy.scrollTo(scrollTarget) }
                }
            }
        }
    }

    /// As big as the open menu, placing each menu in it on its bottom trailing corner at its own size, so
    /// a menu leaving stays where its items are as the panel takes the next one's size.
    struct Panel: Layout {
        /// The layer of the open menu.
        let current: Int?

        struct LayerKey: LayoutValueKey {
            static let defaultValue = -1
        }

        /// Each menu's size, measured once a layout.
        func makeCache(subviews: Subviews) -> [CGSize] {
            subviews.map { $0.sizeThatFits(.unspecified) }
        }

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]) -> CGSize {
            let open = subviews.firstIndex { $0[LayerKey.self] == current } ?? subviews.indices.last
            return open.map { cache[$0] } ?? .zero
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout [CGSize]) {
            for (subview, size) in zip(subviews, cache) {
                subview.place(at: CGPoint(x: bounds.maxX, y: bounds.maxY), anchor: .bottomTrailing, proposal: ProposedViewSize(size))
            }
        }
    }

    /// A menu part of the way out of its button: as big, about its bottom trailing corner, and as faded,
    /// as `progress` says, from `smallest` at 0 to its size at 1.
    struct Growth: ViewModifier, Animatable {
        var progress: Double
        let smallest: CGFloat
        /// Where in its growth it goes from hidden to shown entirely.
        let shows: ClosedRange<Double>
        /// The least it shows: growing, enough that focus can move into it.
        var faintest = Metrics.faintest

        var animatableData: Double {
            get { progress }
            set { progress = newValue }
        }

        func body(content: Content) -> some View {
            content
                .scaleEffect(smallest + (1 - smallest) * progress, anchor: .bottomTrailing)
                .opacity(min(1, max(faintest, (progress - shows.lowerBound) / (shows.upperBound - shows.lowerBound))))
        }
    }

    /// Lays its views out one under another, all as wide as the widest wants to be, within limits.
    struct Stack: Layout {
        let minWidth: CGFloat
        let maxWidth: CGFloat

        /// The width they're laid out at, and each one's height there, measured once a layout.
        struct Cache {
            var width: CGFloat
            var heights: [CGFloat]
        }

        func makeCache(subviews: Subviews) -> Cache {
            let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
            let width = min(maxWidth, max(minWidth, widest))
            return Cache(width: width, heights: subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height })
        }

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
            CGSize(width: cache.width, height: cache.heights.reduce(0, +))
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
            var y = bounds.minY
            for (subview, height) in zip(subviews, cache.heights) {
                subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: height))
                y += height
            }
        }
    }

    /// An item's check, title (with what's chosen under it, for a submenu) and chevron.
    struct ItemLabel: View {
        let item: PlayerMenu.Item

        var body: some View {
            HStack(spacing: 0) {
                Image(systemName: "checkmark")
                    .font(Metrics.checkmarkFont)
                    .frame(width: Metrics.checkmarkWidth)
                    .padding(.trailing, Metrics.textInset - Metrics.rowInset - Metrics.checkmarkWidth)
                    .opacity(item.isChecked ? 1 : 0)
                VStack(alignment: .leading, spacing: Metrics.detailSpacing) {
                    Text(item.title)
                        .font(Metrics.titleFont)
                    if let detail = item.detail {
                        Text(detail)
                            .font(Metrics.detailFont)
                            .opacity(Metrics.secondaryOpacity)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: Metrics.accessorySpacing)
                if item.submenu != nil {
                    Image(systemName: "chevron.right")
                        .font(Metrics.chevronFont)
                        .opacity(Metrics.secondaryOpacity)
                }
            }
            .padding(.leading, Metrics.rowInset)
            .padding(.trailing, Metrics.accessoryInset)
            .frame(height: item.detail == nil ? Metrics.rowHeight : Metrics.detailRowHeight)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(item.isChecked ? .isSelected : [])
        }
    }

    /// A row drawn as it is, white on the panel, or black on a white capsule while it has focus. A menu
    /// leaving hides its focus at once.
    struct ItemButtonStyle: ButtonStyle {
        let showsFocus: Bool

        func makeBody(configuration: Configuration) -> some View {
            Row(configuration: configuration, showsFocus: showsFocus)
        }

        struct Row: View {
            let configuration: Configuration
            let showsFocus: Bool
            @Environment(\.isFocused) private var isFocused

            var body: some View {
                let highlighted = isFocused && showsFocus
                configuration.label
                    .foregroundStyle(highlighted ? .black : .white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        Capsule()
                            .fill(.white.opacity(configuration.isPressed ? Metrics.pressedOpacity : Metrics.focusedOpacity))
                            .padding(.horizontal, Metrics.capsuleInset)
                            .padding(.vertical, -Metrics.capsuleOverhang)
                            .opacity(highlighted ? 1 : 0)
                    }
                    .animation(Metrics.focusMotion, value: isFocused)
                    // Hidden at once as its menu leaves; shown as focus would come to it.
                    .animation(showsFocus ? Metrics.focusMotion : nil, value: showsFocus)
            }
        }
    }

    /// Measured from the TV app's menus at 1080p, ink against ink, and their motion from AVKit's at
    /// 60 fps.
    struct Metrics {
        /// As wide as the TV app's once it has settled, and how much wider long names can make it.
        static let width: CGFloat = 451
        static let maxWidth: CGFloat = 700
        /// As tall as fits above the buttons, under the screen's top margin.
        static let maxHeight: CGFloat = 700
        static let cornerRadius: CGFloat = 56
        static let verticalPadding: CGFloat = 17
        static let headerHeight: CGFloat = 59
        /// Above a header, from the panel's top or a line.
        static let headerTopSpacing: CGFloat = 10
        static let headerInset: CGFloat = 35
        static let separatorSpacing: CGFloat = 19
        static let separatorHeight: CGFloat = 1
        static let separatorOpacity = 0.15
        static let rowHeight: CGFloat = 66
        static let detailRowHeight: CGFloat = 86
        static let detailSpacing: CGFloat = 8
        /// From the panel's edge to the check, and to the text.
        static let rowInset: CGFloat = 46
        static let checkmarkWidth: CGFloat = 24
        static let textInset: CGFloat = 90
        /// From the panel's edge to a chevron's.
        static let accessoryInset: CGFloat = 37
        static let accessorySpacing: CGFloat = 16
        /// The focused capsule: in from the panel's edges, and over the row's.
        static let capsuleInset: CGFloat = 15
        static let capsuleOverhang: CGFloat = 4
        static let focusedOpacity = 0.92
        static let pressedOpacity = 0.6
        static let secondaryOpacity = 0.5
        /// tvOS's caption styles, 23 and 25 points medium: measured against the TV app's text widths
        /// and ink, not tvOS's body (29 points), which the menus first used.
        static var headerFont: Font { .caption2 }
        static var titleFont: Font { .caption }
        static var detailFont: Font { .caption2 }
        /// A check 22 points across, and a chevron 18 tall, as the TV app's.
        static var checkmarkFont: Font { .caption.weight(.semibold) }
        static var chevronFont: Font { .system(size: 21, weight: .semibold) }
        static var focusMotion: Animation { .easeOut(duration: 0.15) }
        /// A menu grows from nothing, a little past its size (1%) and back, nine-tenths there in 0.2 s,
        /// showing entirely once it's grown 60% of the way.
        static let openingScale: CGFloat = 0.01
        static var opening: Animation { .spring(response: 0.43, dampingFraction: 0.84) }
        static let showsOpening = 0.0...0.6
        /// It shrinks toward a fifth of its size as it closes, gone once 85% of the way, 0.14 s in.
        static let closedScale: CGFloat = 0.2
        static var closing: Animation { .spring(response: 0.37, dampingFraction: 0.75) }
        static let showsClosing = 0.15...1.0
        /// A submenu pushing in, and the panel taking its size: AVKit's spring, without bounce, half there
        /// in 0.08 s and nine-tenths in 0.2 s.
        static var push: Animation { .spring(response: 0.31, dampingFraction: 1) }
        /// The least a menu shows as it grows: a view faded out entirely loses focus, and one that starts
        /// out so never takes it, even once it shows.
        static let faintest = 0.02
        /// How long after a submenu starts pushing in focus lands in it: once the panel has all but
        /// stopped, as AVKit's does.
        static let settleDelay = Duration.milliseconds(500)
        /// How long a menu waits, built, before it moves: two frames, so the frames building it took are
        /// drawn first.
        static let buildPause = Duration.milliseconds(34)
        /// How long after a menu starts opening focus moves into it: once it's nine-tenths grown.
        static let focusDelay = Duration.milliseconds(230)
        /// How often, and how many times, focus is asked for until it's there.
        static let focusRetry = Duration.milliseconds(50)
        static let focusAttempts = 30
    }
}
