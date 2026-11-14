import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// Home's banner, filling the screen: the item's backdrop, its details (logo or title, metadata and
/// overview), Play, Info and next buttons, and the system's page indicator. It goes through the newest
/// items, sliding each in over the last (`HomeBannerViewModel`); Left and Right move between them.
/// Continue Watching overlaps its bottom, so its text sits above that. Info makes the banner the item's
/// full-screen detail view (`showsDetails`), moving the details and buttons to where a full-screen card
/// has them.
struct HomeBannerView: View {
    let viewModel: HomeBannerViewModel
    /// The screen's size, which the banner fills.
    let size: CGSize
    /// The screen's safe area, which the text keeps within.
    let safeArea: EdgeInsets
    var focus: FocusState<HomeFocus?>.Binding
    let onInfo: () -> Void
    let onNext: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ZStack(alignment: .topLeading) {
                ForEach(viewModel.layers) { item in
                    backdrop(of: item)
                        // The incoming banner's edge sweeps in from the right (or the left, going
                        // back), uncovering its artwork where it is; the one showing stays whole
                        // underneath.
                        .mask(alignment: viewModel.incomingComesFromLeading ? .leading : .trailing) {
                            Rectangle()
                                .frame(width: viewModel.isIncoming(item) && !viewModel.incomingHasSlidIn ? 0 : size.width)
                        }
                }
            }

            scrim
                .opacity(viewModel.showsLabels && !viewModel.showsDetails ? 1 : 0)
            // A full-screen card's, while it's the detail view.
            MediaCardView.detailsScrim
                .opacity(viewModel.showsDetails ? 1 : 0)

            if let item = viewModel.current {
                labels(for: item)
                    .padding(.leading, viewModel.showsDetails ? MediaCardView.Metrics.fullScreenDetailsLeadingPadding : safeArea.leading)
                    // A strip as wide as the screen and entirely above the first row, which overlaps
                    // the banner's bottom: Up from anywhere along that row finds it, and lands on the
                    // button focus was on last.
                    .frame(width: size.width, alignment: .leading)
                    .focusSection()
                    .defaultFocus(focus, viewModel.lastButton, priority: .userInitiated)
                    .padding(.bottom, viewModel.showsDetails ? MediaCardView.Metrics.detailsBottomMargin : Metrics.buttonsBottomInset)
            }

            PageIndicatorView(
                count: viewModel.items.count,
                current: viewModel.index,
                isCountingDown: viewModel.isCountingDown,
                countdown: viewModel.countdown,
                interval: viewModel.interval
            )
                .fixedSize()
                .frame(maxWidth: .infinity)
                .padding(.bottom, Metrics.indicatorBottomInset)
                .opacity(viewModel.showsDetails ? 0 : 1)
                .accessibilityElement()
                .accessibilityLabel("\(viewModel.index + 1) of \(viewModel.items.count)")
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
    }

    private func backdrop(of item: MediaItem) -> some View {
        RemoteImageView(url: viewModel.card(for: item).landscapeArtworkURL, priority: .high) { image in
            image
                .resizable()
                .scaledToFill()
        } placeholder: {
            ImagePlaceholderView()
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// Where Left or Right from the buttons lands while there's a banner that way. It doesn't fade with
    /// the buttons, since focus can't move to, or stay on, what's faded out entirely, and for the same
    /// reason it isn't clear, only too faint to see.
    private func edgeCatcher(_ edge: HomeFocus, isActive: Bool, width: CGFloat? = Metrics.catcherWidth) -> some View {
        Color.black.opacity(Metrics.focusableOpacity)
            .frame(width: width, height: width == nil ? nil : Metrics.catcherHeight)
            // It stays focusable while it holds focus, even once there's nowhere left to go that way,
            // until it lets focus go: focus asked to move off it otherwise stays put.
            .focusable((isActive || focus.wrappedValue == edge) && viewModel.catchesEdges)
            .focusEffectDisabled()
            .focused(focus, equals: edge)
            .accessibilityHidden(true)
    }

    /// Darkens the corner the text sits in, so it reads over any artwork.
    private var scrim: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(Metrics.scrimOpacity), .clear], startPoint: .leading, endPoint: .center)
            LinearGradient(colors: [.clear, .black.opacity(Metrics.scrimOpacity)], startPoint: .center, endPoint: .bottom)
        }
        .allowsHitTesting(false)
    }

    /// The item's details (its logo or title, metadata and overview) and the buttons, which fade out
    /// while banners move. The details are the very block an item's full-screen card shows, and the card's
    /// actions sit where the buttons are: Info moves them to where the card has them while the banner's
    /// buttons cross-fade into the actions. Whichever holds focus fades only as far as
    /// `focusableOpacity`, so focus stays on it through the move.
    private func labels(for item: MediaItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            MediaDetailInfoView(card: viewModel.card(for: item))
                .frame(width: MediaDetailInfoView.Metrics.width, alignment: .leading)
                // Each item's are its own: the last one's logo doesn't cross-fade into the next one's
                // as the text comes back.
                .id(item.id)
                .padding(.bottom, MediaCardView.Metrics.actionsReservedHeight)
                .opacity(viewModel.showsLabels ? 1 : 0)
            buttons
            MediaDetailActionsView(item: item, focus: focus, focusValue: HomeFocus.detail(item.id), isActive: viewModel.detailsAreAway)
                .opacity(viewModel.showsDetails ? 1 : viewModel.detailsAreAway ? Metrics.focusableOpacity : 0)
        }
    }

    /// Play, Info and next. They, and what catches Left and Right, fade only as far as
    /// `focusableOpacity`, too faint to see: focus can't move to, or stay on, something faded out
    /// entirely, and it stays on the button it's on.
    private var buttons: some View {
        let opacity: Double = viewModel.showsLabels && !viewModel.showsDetails ? 1 : Metrics.focusableOpacity
        return HStack(spacing: Metrics.buttonSpacing) {
            // Left and Right from the buttons move between banners; Left from the first brings in the
            // sidebar, and Right from the last goes round to the first. Handling the move doesn't stop
            // tvOS moving focus into the sidebar, so while there's a banner either way, something
            // focusable waits on that side to catch the move instead.
            Button("Play", systemImage: "play.fill") {}
                .disabled(true)  // Playback comes with #15.
                .opacity(opacity)
                // Right beside the leftmost button, so tvOS finds it before the sidebar.
                // FIXME: Move it left of Play once Play is enabled (#15).
                .background {
                    edgeCatcher(.bannerLeftEdge, isActive: viewModel.hasPrevious, width: nil)
                }
            Button("Info", systemImage: "info.circle", action: onInfo)
                .labelStyle(.iconOnly)
                .focused(focus, equals: .bannerInfo)
                .accessibilityIdentifier("home.banner.info")
                .opacity(opacity)
            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
            .disabled(!viewModel.hasNext)
            .focused(focus, equals: .bannerNext)
            .accessibilityLabel("Next")
            .accessibilityIdentifier("home.banner.next")
            .opacity(opacity)
            edgeCatcher(.bannerRightEdge, isActive: viewModel.hasNext)
        }
        .buttonStyle(.glass)
        .disabled(!viewModel.buttonsTakeFocus)
    }
}

extension HomeBannerView {
    struct Metrics {
        /// How far the first row overlaps the banner's bottom: the browsing view's row spacing (56) is
        /// added below this, so the row's title sits 204 points above the screen's bottom.
        static let rowOverlap: CGFloat = 260
        /// The page indicator's distance from the screen's bottom: just above the first row's title.
        static let indicatorBottomInset: CGFloat = 218
        /// The buttons' distance from the screen's bottom: clear of the page indicator. The details sit
        /// `actionsReservedHeight` above them, as on the full-screen card.
        static let buttonsBottomInset: CGFloat = indicatorBottomInset + 70
        static let buttonSpacing: CGFloat = 24
        static let scrimOpacity = 0.75
        static let catcherWidth: CGFloat = 2
        static let catcherHeight: CGFloat = 60
        /// The least a view can be seen and still take or keep focus: too faint to see.
        static let focusableOpacity = 0.02
    }
}
