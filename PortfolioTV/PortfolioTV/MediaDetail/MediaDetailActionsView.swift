import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// A card's actions, under its details: Play, or Resume where the user left off (`PlayLabelView`), then
/// Information, Add to My Watchlist, the profile's own rating, and, while there's somewhere to resume
/// from, Start from the Beginning. Information opens the item's page below the card (`detailPages`)
/// scrolled all the way down to its facts, and Down opens it on its first row, unless the page is what
/// draws them, which then scrolls to its facts itself (`onInformation`). Once the card is full screen and
/// settled, they build its page ahead, hidden, so it only has to be revealed. Each knows which
/// action has focus (`onFocusChange`), so the page and its card hand focus over on the same action.
/// They sit above the card rather than in it: the card is a button while it's a platter, and buttons
/// can't contain other buttons. Whoever draws them places them, at `fullScreenDetailsLeadingPadding` and
/// `detailsBottomMargin` from the screen's bottom-leading corner on a full-screen card. Once they're in
/// use, they ask where the item plays from, so Play starts sooner.
///
/// Home's banner draws its own Play and Info as these (`banner`), with its › (`trailing`) in the other
/// actions' place until they show, so Info making the banner the item's detail view is the very button
/// moving, focus and all.
struct MediaDetailActionsView<Focus: Hashable, Trailing: View>: View {
    let card: MediaCardViewModel
    var focus: FocusState<Focus?>.Binding
    /// What focus is on the first action: Play, or Information where there's nothing to play with.
    let focusValue: Focus
    /// Whether they're in use: they take focus, and accessibility sees them. Otherwise they're only
    /// shown, as on a platter, or not at all.
    var isActive = true
    /// Plays the item, from the beginning or resuming. Without it, nothing plays, as on the sample rows.
    var onPlay: ((PlaybackStart) -> Void)?
    /// What Information does on the item's page, which draws these at its top. Elsewhere, it opens the
    /// page.
    var onInformation: (() -> Void)?
    /// Told which action has focus as it moves among them, and nil once it leaves them.
    var onFocusChange: ((MediaDetailAction?) -> Void)?
    /// The action focus starts on, on the item's page: the one the card had, so nothing changes as the
    /// page takes over.
    var initialFocus: MediaDetailAction?
    /// Whether to ask for the item's details, so its card has them by the time it's full screen: as a
    /// row's platter is highlighted, say. Unless told, while they're in use.
    var preparesDetails: Bool?
    /// Whether to build the item's page ahead, hidden, so Information and Down only reveal it. Unless
    /// told, while they're in use, which on a card is once it's full screen.
    var buildsPage: Bool?
    /// Home's banner, whose own Play and Info these are, else nil.
    var banner: Banner?
    /// What Home's banner shows after Information, in the other actions' place, until they show: its ›.
    @ViewBuilder let trailing: Trailing

    /// Which action has focus, so focus can come back to the same one from the item's page.
    @FocusState private var focusedAction: MediaDetailAction?
    /// Whether the rating's panel is there, over the star, and whether it has grown out of it: it grows
    /// and shrinks as state, not a transition, as the player's menus do, since focus can't move onto a
    /// view whose transition is still running.
    @State private var isRating = false
    @State private var showsRating = false
    @FocusState private var ratingRow: MediaDetailRatingView.Row?
    /// Whether focus is in the rating's panel, or on its way there: the star is disabled meanwhile, so
    /// focus stays in the panel, and enabled again before focus comes back to it.
    @State private var ratingHoldsFocus = false
    /// Where the star is among the actions, and how tall they are, to open the panel over it.
    @State private var starFrame: CGRect = .zero
    @State private var height: CGFloat = 0

    @Environment(\.preparePlayback) private var preparePlayback
    @Environment(\.prepareDetails) private var prepareDetails
    @Environment(\.detailPages) private var detailPages
    @Environment(\.profilePreferences) private var profilePreferences

    var body: some View {
        let showsActions = banner?.showsActions ?? true
        HStack(spacing: showsActions ? Metrics.spacing : banner?.spacing ?? Metrics.spacing) {
            Group {
                Button { onPlay?(card.playStart) } label: {
                    PlayLabelView(card: card)
                }
                .disabled(onPlay == nil || isRating)
                .focused(focus, equals: focusValue, isFirst: onPlay != nil)
                .focused($focusedAction, equals: .play)
                Button("Information", systemImage: "info.circle", action: information)
                    .labelStyle(.iconOnly)
                    .disabled(isRating)
                    .focused(focus, equals: banner?.informationFocus ?? focusValue, isFirst: banner != nil || onPlay == nil)
                    .focused($focusedAction, equals: .information)
            }
            // The banner's own Play and Info, in use whether the other actions are or not, and fading
            // with its text while banners move.
            .disabled(banner == nil && !isActive)
            .opacity(banner?.opacity ?? 1)
            ZStack(alignment: .leading) {
                HStack(spacing: Metrics.spacing) {
                    // FIXME: Add the item to the user's "My Watchlist" playlist, and show it's there (#39).
                    Button("Add to My Watchlist", systemImage: "plus") {}
                        .labelStyle(.iconOnly)
                        .disabled(true)
                    if let profilePreferences {
                        rating(in: profilePreferences)
                            .focused($focusedAction, equals: .rating)
                    }
                    if card.canResume {
                        Button("Start from the Beginning", systemImage: "arrow.counterclockwise") { onPlay?(.beginning) }
                            .labelStyle(.iconOnly)
                            .disabled(onPlay == nil || isRating)
                            .focused($focusedAction, equals: .startFromBeginning)
                    }
                }
                // Under the banner's › until they show, as faint as still keeps focus while they come
                // and go, so focus stays on the one it's on.
                .opacity(showsActions ? 1 : isActive ? Metrics.faintest : 0)
                .disabled(!isActive)
                .accessibilityHidden(!showsActions)
                trailing
            }
        }
        .buttonStyle(.glass)
        // Over the actions rather than in the star's overlay: a glass button that's disabled, as the
        // star is while focus is in the panel, took the presses of everything drawn in it.
        .overlay(alignment: .bottomLeading) {
            if isRating, let profilePreferences {
                MediaDetailRatingView(item: card.item, preferences: profilePreferences, focus: $ratingRow, onClose: closeRating)
                    .fixedSize()
                    .scaleEffect(showsRating ? 1 : Menu.closedScale, anchor: .bottom)
                    .opacity(showsRating ? 1 : Menu.faintest)
                    // Its bottom above the star, centered on it.
                    .padding(.bottom, height + MediaDetailRatingView.Metrics.buttonSpacing)
                    .offset(x: starFrame.midX - Menu.width / 2)
            }
        }
        .coordinateSpace(.named(Self.space))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        // Inactive, one element that ignores its buttons, hidden: hiding the buttons alone left them
        // where XCUITest finds them. The banner's own buttons are always there.
        .accessibilityElement(children: isActive || banner != nil ? .contain : .ignore)
        .accessibilityHidden(!isActive && banner == nil)
        .accessibilityIdentifier(isActive && showsActions ? "detail.fullScreen" : "")
        .onChange(of: isActive && onPlay != nil, initial: true) { _, playable in
            if playable { preparePlayback(card.item) }
        }
        .onChange(of: preparesDetails ?? isActive, initial: true) { _, prepares in
            if prepares { prepareDetails(card) }
        }
        // Built once the card has stopped growing, so building it doesn't hold up the motion. Only a card
        // builds its page: the page's own actions, at its top, leave it be.
        .task(id: buildsPage ?? isActive) {
            guard onInformation == nil else { return }
            guard buildsPage ?? isActive else {
                detailPages.discard(card)
                return
            }
            try? await Task.sleep(for: Metrics.pageBuildDelay)
            guard !Task.isCancelled else { return }
            detailPages.prepare(card)
        }
        .onChange(of: focusedAction) { _, action in onFocusChange?(action) }
        // Put away with its card.
        .onChange(of: isActive) { _, active in
            if !active { isRating = false; showsRating = false; ratingHoldsFocus = false }
        }
        .modifier(InitialFocus(focusedAction: $focusedAction, action: initialFocus))
        // Down from a full-screen card goes on to its page, as in the TV app. Always there, as the
        // actions change only what they hold as they come into use: built again then, under Home's
        // banner, they held up its move to its detail view.
        .onMoveCommand { direction in
            if direction == .down, opensPage { showDetails(at: .sections) }
        }
    }

    /// Whether Down opens the item's page: while they're in use on a card, or once Home's banner is its
    /// item's detail view, not on the page that draws them at its top.
    private var opensPage: Bool {
        isActive && !isRating && onInformation == nil && banner?.onInfo == nil
    }

    /// Information: on Home's banner, until it's the item's detail view, makes it so; otherwise it opens
    /// the item's page at its facts.
    private func information() {
        if let onInfo = banner?.onInfo {
            onInfo()
        } else {
            showDetails(at: .facts)
        }
    }

    /// Opens the item's page at `destination`, or on the page, scrolls to its facts.
    private func showDetails(at destination: MediaDetailDestination) {
        if let onInformation {
            onInformation()
        } else {
            detailPages.open(card, at: destination, from: focusedAction) { [focus, focusValue, $focusedAction, canFocus] action in
                // On the action it came back to, if the card has it, else the first: the page can always
                // play, and a sample row's card can't.
                if let action, canFocus(action) {
                    $focusedAction.wrappedValue = action
                } else {
                    focus.wrappedValue = focusValue
                }
            }
        }
    }

    /// Whether `action` can take focus here.
    private func canFocus(_ action: MediaDetailAction) -> Bool {
        switch action {
        case .play: onPlay != nil
        case .information: true
        case .rating: profilePreferences != nil
        case .startFromBeginning: onPlay != nil && card.canResume
        }
    }

    /// The profile's own rating of the item, half a star to 5, kept on this device: a star, filled once
    /// it's rated, that opens its panel over it (`MediaDetailRatingView`).
    private func rating(in preferences: ProfilePreferences) -> some View {
        let stars = preferences.rating(of: card.item)
        return Button(action: openRating) {
            Label("Rate", systemImage: stars == nil ? "star" : "star.fill")
                .labelStyle(.iconOnly)
        }
        // Once focus is in its panel, so focus stays there.
        .disabled(ratingHoldsFocus)
        .accessibilityValue(stars.map { "\($0.formatted()) stars" } ?? "Not rated")
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { starFrame = $0 }
    }

    /// The actions' own coordinates, where the star's frame is measured.
    private static var space: String { "actions" }

    /// Grows the rating's panel out of the star, as the player's menus grow out of their buttons, once
    /// it's built, then moves focus into it once it has nearly grown.
    private func openRating() {
        isRating = true
        Task {
            try? await Task.sleep(for: Menu.buildPause)
            withAnimation(Menu.opening) { showsRating = true }
            try? await Task.sleep(for: Menu.focusDelay)
            ratingRow = .stars(halves: MediaDetailRatingView.halves(of: profilePreferences?.rating(of: card.item) ?? 0))
            ratingHoldsFocus = true
        }
    }

    /// Gives focus back to the star, then shrinks the rating's panel back into it. The star is enabled
    /// first, and takes focus a moment later, once it can: asked at once, focus went to Play as the
    /// panel went.
    private func closeRating() {
        ratingHoldsFocus = false
        Task {
            focusedAction = .rating
            withAnimation(Menu.closing, completionCriteria: .logicallyComplete) {
                showsRating = false
            } completion: {
                isRating = false
            }
        }
    }

    private typealias Menu = PlayerMenuView.Metrics
}

/// Starts focus on `action`, if there's one: on the item's page, the action the card had. Without one,
/// it asks nothing: a default focus of none, on the hidden actions under Home's banner, kept focus from
/// the banner's buttons, so Home opened on the first row and Right from Play didn't reach Info.
private struct InitialFocus: ViewModifier {
    var focusedAction: FocusState<MediaDetailAction?>.Binding
    let action: MediaDetailAction?

    func body(content: Content) -> some View {
        if let action {
            content.defaultFocus(focusedAction, action, priority: .userInitiated)
        } else {
            content
        }
    }
}

private extension View {
    /// Binds focus to `value` only when this is the first action that can take it.
    @ViewBuilder func focused<Value: Hashable>(_ focus: FocusState<Value?>.Binding, equals value: Value, isFirst: Bool) -> some View {
        if isFirst {
            focused(focus, equals: value)
        } else {
            self
        }
    }
}

/// Where an item's page opens: on its first row, as Down does, or all the way down at its facts, as
/// Information does, or at its top, on its actions, for a page with no card under it: an episode's,
/// opened from its show's row.
enum MediaDetailDestination: Hashable {
    case sections
    case facts
    case card
}

/// One of a card's actions.
enum MediaDetailAction: Hashable {
    case play
    case information
    case rating
    case startFromBeginning
}

extension MediaDetailActionsView where Trailing == EmptyView {
    /// A card's actions, or its page's, with nothing of Home's banner's among them.
    init(
        card: MediaCardViewModel,
        focus: FocusState<Focus?>.Binding,
        focusValue: Focus,
        isActive: Bool = true,
        onPlay: ((PlaybackStart) -> Void)? = nil,
        onInformation: (() -> Void)? = nil,
        onFocusChange: ((MediaDetailAction?) -> Void)? = nil,
        initialFocus: MediaDetailAction? = nil,
        preparesDetails: Bool? = nil,
        buildsPage: Bool? = nil
    ) {
        self.init(
            card: card,
            focus: focus,
            focusValue: focusValue,
            isActive: isActive,
            onPlay: onPlay,
            onInformation: onInformation,
            onFocusChange: onFocusChange,
            initialFocus: initialFocus,
            preparesDetails: preparesDetails,
            buildsPage: buildsPage,
            banner: nil
        ) {
            EmptyView()
        }
    }
}

extension MediaDetailActionsView {
    /// How Home's banner draws its own buttons as these: its Play and Info are Play and Information,
    /// in use whether the other actions are or not, so Info making the banner the item's detail view
    /// moves the very button focus is on. Its › sits in the other actions' place until they show.
    struct Banner {
        /// Whether the other actions show, in place of the banner's ›: while it's the item's detail view.
        var showsActions: Bool
        /// The space between the banner's own buttons, which widens to the actions' as they show.
        var spacing: CGFloat
        /// How much Play and Information show: they fade with the banner's text while banners move,
        /// only as far as still keeps focus.
        var opacity: Double
        /// What focus is on Information: the banner's Info. Play's is `focusValue`.
        var informationFocus: Focus
        /// What Information does in place of opening the item's page: until the banner is its item's
        /// detail view, makes it so, and nothing while it's on its way. Nil once it's there, so
        /// Information and Down open the page.
        var onInfo: (() -> Void)?
    }

    // Computed: a generic type's nested types can't have stored static properties.
    struct Metrics {
        static var spacing: CGFloat { 32 }
        /// How long after the card is full screen its page is built: once it has stopped growing.
        static var pageBuildDelay: Duration { .milliseconds(600) }
        /// The least a view can be seen and still take or keep focus: too faint to see.
        static var faintest: Double { 0.02 }
    }
}
