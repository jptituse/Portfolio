import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// Poster rows that open the way the Apple TV app's do:
///
/// 1. **Select a poster:** every poster in its row grows, together, into a platter. The selected one
///    is inset in the middle and runs to the bottom of the screen; its neighbors sit to the sides.
///    Left and Right move between them.
/// 2. **Select or Down on a platter:** it grows to fill the screen, pushing its neighbors off the sides.
/// 3. **Menu** reverses each step, shrinking the cards back onto their posters at the end.
///
/// Each group is drawn by `RelatedMediaGroupPosterView` at rest and by `RelatedMediaGroupCarouselView`
/// once it's open. `MediaBrowsingViewModel` moves the cards between layers, and everything in this view
/// inherits the layer it's in as its `ViewState`.
struct MediaBrowsingView<Header: View>: View {
    let header: Header
    let topPadding: CGFloat
    let scrollToTopRequests: Int
    let showsRows: Bool
    let canScroll: Bool

    @State private var viewModel: MediaBrowsingViewModel
    @FocusState private var focus: BrowsingFocus?
    @Environment(\.displayScale) private var displayScale

    /// - Parameters:
    ///   - images: where the items' artwork comes from. Without it, cards show a placeholder.
    ///   - topPadding: room above the header, inside the safe area. A header that reaches the top of
    ///     the screen, such as Home's banner, has none, and draws past the safe area itself: nothing
    ///     here clips it.
    ///   - scrollToTopRequests: goes up each time the view should scroll back to its top. It's a request
    ///     each time rather than a position kept: a scroll position held for the scroll view puts it
    ///     back there whenever the view updates, such as while a row opens or closes.
    ///   - showsRows: whether the rows show, under the header. They fade with the change.
    ///   - canScroll: whether the view scrolls, including to show what gets focus.
    init(
        groups: [RelatedMediaGroup],
        images: (any MediaImageResolver)? = nil,
        topPadding: CGFloat = Metrics.verticalPadding,
        scrollToTopRequests: Int = 0,
        showsRows: Bool = true,
        canScroll: Bool = true,
        @ViewBuilder header: () -> Header
    ) {
        _viewModel = State(initialValue: MediaBrowsingViewModel(groups: groups, images: images))
        self.topPadding = topPadding
        self.scrollToTopRequests = scrollToTopRequests
        self.showsRows = showsRows
        self.canScroll = canScroll
        self.header = header()
    }

    var body: some View {
        let openGroup = viewModel.openGroup
        ZStack {
            browsing
                .disabled(viewModel.cardsHoldFocus)
                // Once the cards give up focus it falls back here, onto the poster they closed on.
                .defaultFocus($focus, viewModel.posterToReturnTo, priority: .userInitiated)

            // Dims the other rows behind the open one.
            Color.black
                .opacity(viewModel.viewState == .preview ? Metrics.backdropOpacity : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            GeometryReader { proxy in
                if let openGroup {
                    RelatedMediaGroupCarouselView(
                        viewModel: openGroup,
                        globalFrame: proxy.frame(in: .global),
                        focus: $focus,
                        onExpand: { viewModel.expand($0, focus: $focus) }
                    )
                    // The cards appear exactly on top of their posters, so they must not fade in.
                    .transition(.identity)
                    .onAppear { viewModel.growIntoPreview(focus: $focus) }
                }
            }
            .ignoresSafeArea()
            .onGeometryChange(for: CGSize.self, of: \.screenSize) { size in
                viewModel.setScreen(scale: displayScale, size: size)
            }
        }
        .environment(\.viewState, viewModel.viewState)
        .onExitCommand(perform: viewModel.canStepBack ? { viewModel.stepBack(focus: $focus) } : nil)
        .onChange(of: focus) { _, newValue in viewModel.focusMoved(to: newValue) }
        .onChange(of: openGroup == nil) { _, isClosed in
            if isClosed { viewModel.groupDidClose() }
        }
    }

    private var browsing: some View {
        ScrollViewReader { scroller in
            rows
                .onChange(of: scrollToTopRequests) {
                    withAnimation(Metrics.scrollToTop) { scroller.scrollTo(Metrics.topID, anchor: .top) }
                }
        }
    }

    private var rows: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                header
                    .id(Metrics.topID)
                ForEach(viewModel.groups) { group in
                    RelatedMediaGroupPosterView(viewModel: group, isOpen: viewModel.isOpen(group), focus: $focus) { item in
                        viewModel.select(item, in: group)
                    }
                    // Coming back from the next row, or from above, lands on the poster focus left.
                    .defaultFocus($focus, viewModel.posterToComeBack(to: group), priority: .userInitiated)
                    .opacity(showsRows ? 1 : 0)
                }
            }
            .padding(.top, topPadding)
            .padding(.bottom, Metrics.verticalPadding)
        }
        // Content scrolls on past the safe area, up to the screen's edges.
        .scrollClipDisabled()
        .scrollDisabled(!canScroll)
    }
}

extension MediaBrowsingView {
    struct Metrics {
        static var rowSpacing: CGFloat { 56 }
        static var verticalPadding: CGFloat { 40 }
        static var backdropOpacity: Double { 0.85 }
        static var scrollToTop: Animation { .smooth(duration: 0.4) }
        static var topID: String { "browsing.top" }
    }
}

#Preview {
    NavigationStack {
        MediaBrowsingView(groups: [.sample]) {
            Text("Home").font(.title)
        }
    }
}
