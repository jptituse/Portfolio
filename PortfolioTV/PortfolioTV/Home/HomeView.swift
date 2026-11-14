import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// The open profile's Home: a banner filling the screen that goes through what was added most
/// recently, then Continue Watching, overlapping the banner's bottom, and the latest of each library.
/// The banner's Info makes it the item's full-screen detail view. Home loads again each time it's shown.
struct HomeView: View {
    let viewModel: HomeViewModel
    /// Whether Home is the section on screen. Sections stay alive while another one shows.
    let isShowing: Bool

    @State private var banner: HomeBannerViewModel
    @State private var safeArea = EdgeInsets()
    @State private var screen = CGSize(width: 1920, height: 1080)
    /// Goes up each time focus comes up into the banner, which scrolls back to the top, so the whole
    /// banner shows.
    @State private var scrollToTopRequests = 0
    @FocusState private var focus: HomeFocus?
    @Environment(\.displayScale) private var displayScale

    init(viewModel: HomeViewModel, isShowing: Bool) {
        self.viewModel = viewModel
        self.isShowing = isShowing
        _banner = State(initialValue: HomeBannerViewModel(images: viewModel.images))
    }

    var body: some View {
        content
        .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { safeArea = $0 }
        .onGeometryChange(for: CGSize.self, of: \.screenSize) { size in
            screen = size
            banner.setScreen(scale: displayScale, size: size)
        }
        .onChange(of: viewModel.bannerItems, initial: true) { _, items in banner.setItems(items) }
        .onChange(of: focus) { old, focus in
            // Coming up into the banner shows all of it.
            if focus != nil, old == nil {
                scrollToTopRequests += 1
            }
            switch focus {
            case .bannerInfo, .bannerNext:
                if let focus { banner.buttonFocused(focus) }
            // Left or Right from the banner's buttons landed just past them: move to the banner that
            // way, focus coming back to the button it left. Coming from anywhere else, such as up
            // from the rows, focus only goes on to the button it was on last.
            case .bannerLeftEdge where old == .bannerInfo || old == .bannerNext:
                banner.previous { returnFocus(to: banner.lastButton) }
            case .bannerRightEdge where old == .bannerInfo || old == .bannerNext:
                banner.next { returnFocus(to: banner.lastButton) }
            case .bannerLeftEdge, .bannerRightEdge:
                returnFocus(to: banner.lastButton)
            default:
                break
            }
        }
        .onChange(of: isShowing, initial: true) { _, isShowing in
            updateAdvancing(isShowing: isShowing)
        }
        .onExitCommand(perform: exitAction)
        .task(id: isShowing) {
            if isShowing { await viewModel.load() }
        }
    }

    /// What Back does: closes the banner's detail view while it's open (and while it moves, nothing), and
    /// otherwise what it always does.
    private var exitAction: (() -> Void)? {
        guard banner.detailsAreAway else { return nil }
        return { closeDetails() }
    }

    private func updateAdvancing(isShowing: Bool) {
        if isShowing, !banner.detailsAreAway {
            banner.startAdvancing()
        } else {
            banner.stopAdvancing()
        }
    }

    @ViewBuilder private var content: some View {
        if viewModel.bannerItems.isEmpty && viewModel.groups.isEmpty {
            status
        } else if viewModel.bannerItems.isEmpty {
            MediaBrowsingView(groups: viewModel.groups, images: viewModel.images) { EmptyView() }
                .id(viewModel.groups)
        } else {
            // The rows fade while the banner is its item's detail view, and the page holds still until
            // the banner's back.
            MediaBrowsingView(
                groups: viewModel.groups,
                images: viewModel.images,
                topPadding: 0,
                scrollToTopRequests: scrollToTopRequests,
                showsRows: !banner.showsDetails,
                canScroll: !banner.detailsAreAway
            ) {
                HomeBannerView(viewModel: banner, size: screen, safeArea: safeArea, focus: $focus, onInfo: openDetails, onNext: showNextBanner)
                    // To the screen's edges, past the safe area the browsing view keeps to.
                    .padding(.top, -safeArea.top)
                    .padding(.leading, -safeArea.leading)
                    .padding(.trailing, -safeArea.trailing)
                    // The first row overlaps the banner's bottom.
                    .padding(.bottom, -HomeBannerView.Metrics.rowOverlap)
            }
            // The browsing view starts over with the rows once they've loaded, or when they change.
            .id(viewModel.groups)
        }
    }

    /// While there's nothing to show: loading, or why not, and a way to try again.
    private var status: some View {
        VStack(spacing: Metrics.statusSpacing) {
            if viewModel.isLoading {
                ProgressView()
            } else if let message = viewModel.message {
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if viewModel.canRetry {
                    Button("Try Again") {
                        Task { await viewModel.load() }
                    }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("home.retry")
                }
            }
        }
        .frame(maxWidth: Metrics.statusWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Makes the banner its item's full-screen detail view: it moves its details and buttons to where a
    /// full-screen card has them, focus staying on Info, then focus moves to the actions.
    private func openDetails() {
        guard let item = banner.current, banner.isIdle else { return }
        let focus = $focus
        banner.showDetails {
            moveFocus(focus, to: .detail(item.id))
        }
    }

    /// The › button: the next banner, the first after the last.
    private func showNextBanner() {
        banner.next()
    }

    /// Brings focus back from where a move between banners was caught, once the buttons are back.
    /// Focus waits there, unseen, while they're faded out: it can't move to them then. Asked to move
    /// straight from there, it doesn't, so the catcher lets it go first.
    private func returnFocus(to target: HomeFocus) {
        let binding = $focus
        banner.releaseEdges {
            try? await Task.sleep(for: Metrics.focusReturnDelay)
            binding.wrappedValue = target
            try? await Task.sleep(for: Metrics.focusReturnDelay)
        }
    }

    /// Back from the detail view: the banner moves everything back, focus staying on the action it's on,
    /// then focus returns to the button it was on last, and the banner moves on by itself again.
    private func closeDetails() {
        let focus = $focus
        let isShowing = isShowing
        banner.hideDetails {
            moveFocus(focus, to: banner.lastButton)
            if isShowing { banner.startAdvancing() }
        }
    }

    /// Moves focus once a move of the details is over, and then lets the buttons it left stop taking
    /// focus: focus can only move to what's still focusable.
    private func moveFocus(_ focus: FocusState<HomeFocus?>.Binding, to target: HomeFocus) {
        focus.wrappedValue = target
        Task { @MainActor in
            try? await Task.sleep(for: Metrics.focusReturnDelay)
            banner.settled()
        }
    }
}

extension HomeView {
    struct Metrics {
        static let statusSpacing: CGFloat = 24
        static let statusWidth: CGFloat = 1000
        /// How long focus waits, after Left on the banner, for the buttons to be back before it returns.
        static let focusReturnDelay: Duration = .milliseconds(50)
    }
}

#if DEBUG
#Preview {
    NavigationStack { HomeView(viewModel: .preview(), isShowing: true) }
}
#endif
