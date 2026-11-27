import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// An item's page, as the TV app's product page: its full-screen card at the top, then, scrolling down,
/// a show's seasons and episodes, its cast and crew, items like it, what it's about, and a block of facts
/// (information, languages, accessibility and its file).
///
/// It's built ahead, hidden (`isRevealed`), once its card is full screen, so Information or Down only
/// reveals it. It opens over the full-screen card it grows out of, looking just like it, and scrolls the
/// card's details away at once, the card's backdrop staying where it is as it blurs under a gray wash and the
/// item's logo arrives at the top. Back at the top, it hands over to the card again (`onClose`), which
/// it still looks just like. Focus moving between the card's actions and the sections scrolls between
/// them; within the sections, tvOS scrolls to whatever has focus.
///
/// A similar item grows from its poster straight to full screen, as a library's do, and its
/// Information opens its own page over this one.
struct MediaDetailPageView: View {
    let viewModel: MediaDetailViewModel
    /// Whether it shows, rather than built ahead, hidden.
    let isRevealed: Bool
    /// Where it opens: on its first row, or all the way down at its facts.
    let destination: MediaDetailDestination
    /// The card's action that had focus as the page opened, which focus starts on, so nothing changes
    /// as it takes over.
    let openedFrom: MediaDetailAction?
    /// Plays an item, from the beginning or resuming.
    let onPlay: PlayAction
    /// Back at the top, where it looks just like the full-screen card under it, with the action that
    /// has focus, if any.
    let onClose: (MediaDetailAction?) -> Void

    @Environment(\.displayScale) private var displayScale
    @Environment(\.hidesSpoilers) private var hidesSpoilers
    @Environment(\.detailPages) private var detailPages
    @FocusState private var focus: MediaDetailFocus?
    @State private var expansion = MediaCardExpansionViewModel()
    /// How far the card has scrolled away. Only the backdrop and the logo read it, so the rest of the
    /// page isn't built again on every frame of a scroll.
    @State private var scroll = Scroll()
    /// Whether it has scrolled away from the top since it opened.
    @State private var hasLeftTop = false
    /// The full text of a tile or column, over the page, while it shows.
    @State private var panel: MediaDetailPanel?
    /// The card's action that has focus, while one has.
    @State private var focusedAction: MediaDetailAction?
    /// Whether focus has gone on to the sections since the page opened.
    @State private var hasEnteredSections = false
    /// Whether focus is on its way into the sections as the page opens, which scrolls to them. Focus
    /// coming back from a panel or a similar item's card, from nowhere on the page, is where it was:
    /// scrolled to the sections' top as well, the page jumped up and back.
    @State private var isEntering = false

    var body: some View {
        GeometryReader { proxy in
            let screen = proxy.size
            ZStack {
                Backdrop(card: viewModel.card, scroll: scroll, screen: screen)
                ScrollViewReader { reader in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 0) {
                            hero(screen: screen)
                                .id(Area.card)
                            // At least as tall as the screen, so the card always scrolls all the way
                            // away and the material covers its backdrop: on a page with little below
                            // the card, it stopped partway, the card's details still at the top, the
                            // backdrop showing through.
                            sections(screen: screen)
                                .frame(minHeight: screen.height, alignment: .top)
                                .id(Area.sections)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                        scroll.progress = min(1, max(0, offset / screen.height))
                        if offset > Metrics.leftTop, !hasLeftTop { hasLeftTop = true }
                    }
                    .onScrollPhaseChange { _, phase in
                        // Back at the top, the card takes over, if there's one under it.
                        if phase == .idle, hasLeftTop, scroll.progress == 0, focusedAction != nil, destination != .card { onClose(focusedAction) }
                    }
                    .onChange(of: area) { old, area in
                        guard let area, old != nil || isEntering else { return }
                        isEntering = false
                        // All the way down to the facts at the end, or the card or the sections' top.
                        withAnimation(Metrics.scroll) {
                            if area == .sections, case .column = focus {
                                reader.scrollTo(Area.sections, anchor: .bottom)
                            } else {
                                reader.scrollTo(area, anchor: .top)
                            }
                        }
                    }
                }
                .disabled(expansion.blocksFocus || panel != nil)

                expandedSimilarItem

                if let panel {
                    MediaDetailPanelView(panel: panel) { close(panel) }
                        .transition(Metrics.panelTransition)
                }
            }
            .animation(Metrics.panelMotion, value: panel)
            .onChange(of: screen, initial: true) { _, screen in
                viewModel.setArtworkSizes(
                    poster: Metrics.posterSize,
                    screen: screen,
                    logo: MediaCardView.Metrics.detailsLogoSize,
                    still: MediaDetailEpisodeView.Metrics.stillSize,
                    scale: displayScale
                )
            }
        }
        .ignoresSafeArea()
        // Built ahead, hidden, it's one element without its identifier: XCUITest on tvOS still lists
        // what's hidden from accessibility.
        .accessibilityElement(children: isRevealed ? .contain : .ignore)
        .accessibilityIdentifier(isRevealed ? "detail.page" : "")
        .onExitCommand(perform: back)
        .task { await viewModel.load() }
        // Opened from the card's Information, or Down: on to the sections at once if they're in, as they
        // usually are, asked for as the card first expanded; else once they are.
        .onChange(of: isRevealed, initial: true) { _, revealed in
            if revealed {
                if destination == .card {
                    // On its actions, with nothing under it to hand focus over from.
                    Task { focus = .actions }
                } else if firstSection != nil {
                    Task { enterSections() }
                }
            } else {
                // Hidden again, back at the top, ready for the card's next Down.
                hasEnteredSections = false
                hasLeftTop = false
                panel = nil
            }
        }
        .onChange(of: firstSection) { _, first in
            if isRevealed, destination != .card, first != nil { enterSections() }
        }
        // An episode's page is built ahead once focus rests on its text, so selecting it only reveals
        // it: built as it opened, it held up its own fade, and its details came in after.
        .task(id: episodeTextFocus) {
            guard isRevealed, let episode = episodeTextFocus, let card = viewModel.pageCard(forEpisode: episode) else { return }
            try? await Task.sleep(for: Metrics.episodePageBuildDelay)
            guard !Task.isCancelled else { return }
            detailPages.prepare(card, opensAt: .card)
        }
        .onChange(of: episodeTextFocus) { left, _ in
            if let left, let card = viewModel.pageCard(forEpisode: left) { detailPages.discard(card) }
        }
    }

    /// The episode whose text has focus, in the show's row.
    private var episodeTextFocus: MediaItem.ID? {
        if case .episodeInfo(let episode) = focus { episode } else { nil }
    }

    // MARK: Card

    /// The card's details, credits and actions, laid out as on the full-screen card, as tall as the
    /// screen.
    private func hero(screen: CGSize) -> some View {
        Color.clear
            .frame(width: screen.width, height: screen.height)
            .overlay(alignment: .bottomTrailing) {
                MediaDetailCreditsView(card: viewModel.card)
                    .padding(.trailing, MediaCardView.Metrics.fullScreenDetailsLeadingPadding)
                    .padding(.bottom, MediaCardView.Metrics.detailsBottomMargin)
            }
            .overlay(alignment: .bottomLeading) {
                // An episode's own page, with no card under it, is titled by the episode, under its show.
                MediaDetailInfoView(card: viewModel.card, titlesEpisode: destination == .card)
                    .frame(width: MediaDetailInfoView.Metrics.width, alignment: .leading)
                    .padding(.leading, MediaCardView.Metrics.fullScreenDetailsLeadingPadding)
                    .padding(.bottom, MediaCardView.Metrics.detailsBottomMargin + MediaCardView.Metrics.actionsReservedHeight)
            }
            .overlay(alignment: .bottomLeading) {
                MediaDetailActionsView(
                    card: viewModel.card,
                    focus: $focus,
                    focusValue: .actions,
                    isActive: isRevealed,
                    onPlay: { onPlay(viewModel.item, $0, nil) },
                    onInformation: { focus = factsFocus ?? firstSection },
                    onFocusChange: { focusedAction = $0 },
                    initialFocus: openedFrom ?? .information
                )
                .padding(.leading, MediaCardView.Metrics.fullScreenDetailsLeadingPadding)
                .padding(.bottom, MediaCardView.Metrics.detailsBottomMargin)
            }
            .focusSection()
    }

    // MARK: Sections

    private func sections(screen: CGSize) -> some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            Logo(viewModel: viewModel, scroll: scroll)
                .frame(maxWidth: .infinity)
            if !viewModel.episodes.isEmpty {
                MediaDetailEpisodesView(viewModel: viewModel, focus: $focus) { card in
                    onPlay(card.item, card.playStart, nil)
                } onOpen: { card in
                    // Its own page, over this one, on its Play, and back to its text after.
                    detailPages.open(viewModel.pageCard(for: card), at: .card, from: .play) { [focus = $focus] _ in
                        focus.wrappedValue = .episodeInfo(card.item.id)
                    }
                }
            }
            if !viewModel.people.isEmpty {
                row("Cast & Crew") {
                    ForEach(viewModel.people) { person in
                        MediaDetailPersonView(
                            name: person.name,
                            role: person.role,
                            pictureURL: viewModel.pictureURL(of: person, pixelSize: Metrics.pictureSize * displayScale)
                        )
                        .focused($focus, equals: .person(person.id))
                    }
                }
            }
            if !viewModel.similar.isEmpty {
                row("Related") {
                    ForEach(viewModel.similar, id: \.item.id) { card in
                        similarPoster(card)
                    }
                }
            }
            about
            facts(screen: screen)
        }
        .padding(.top, Metrics.sectionsTopPadding)
    }

    /// A titled row that scrolls sideways, to the screen's edges.
    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Metrics.titleSpacing) {
            sectionTitle(title)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Metrics.itemSpacing) {
                    content()
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .contentMargins(.horizontal, Metrics.margin, for: .scrollContent)
        }
        .focusSection()
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(Metrics.sectionTitleFont)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Metrics.margin)
    }

    /// A similar item's poster, which grows to full screen when selected, as a library's.
    private func similarPoster(_ card: MediaCardViewModel) -> some View {
        Button {
            expansion.select(card)
        } label: {
            MediaCardView(viewModel: card)
                .frame(width: Metrics.posterSize.width, height: Metrics.posterSize.height)
                .contentShape(.hoverEffect, .rect(cornerRadius: MediaCardView.Metrics.posterCornerRadius))
                .hoverEffect(.highlight)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    expansion.posterMoved(card.item.id, to: frame)
                }
        }
        .buttonStyle(MediaCardButtonStyle())
        // Hidden under its card while that's open, as faint as still takes focus, for its card to hand
        // focus back to.
        .opacity(expansion.item == card.item.id ? MediaCardExpansionViewModel.hiddenPosterOpacity : 1)
        .focused($focus, equals: .similar(card.item.id))
        .environment(\.viewState, .root)
        .accessibilityLabel(card.item.name)
    }

    /// The overview, then the scores.
    private var about: some View {
        VStack(alignment: .leading, spacing: Metrics.titleSpacing) {
            sectionTitle("About")
            HStack(alignment: .top, spacing: Metrics.tileSpacing) {
                Button { panel = .overview(viewModel) } label: {
                    VStack(alignment: .leading, spacing: Metrics.tileTextSpacing) {
                        Text(viewModel.item.name)
                            .font(.headline)
                        if let genres = viewModel.genres {
                            Text(genres)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let overview = viewModel.overview {
                            Text(overview)
                                .font(.callout)
                                .lineLimit(Metrics.overviewLineLimit)
                                .padding(.top, Metrics.tileTextSpacing)
                        }
                    }
                    .frame(width: Metrics.overviewTileWidth, height: Metrics.tileHeight, alignment: .topLeading)
                }
                .focused($focus, equals: .overview)
                ForEach(viewModel.ratings) { rating in
                    Button {} label: {
                        VStack(alignment: .leading, spacing: Metrics.tileTextSpacing) {
                            Text(rating.value)
                                .font(.largeTitle)
                                .bold()
                            Text(rating.label)
                                .font(.headline)
                        }
                        .frame(width: Metrics.ratingTileWidth, height: Metrics.tileHeight, alignment: .topLeading)
                    }
                    .focused($focus, equals: .rating(rating.id))
                }
            }
            .buttonStyle(TileButtonStyle())
            .padding(.horizontal, Metrics.margin)
        }
        .focusSection()
    }

    /// Information, Languages, Accessibility and the file, side by side on a darker band, which runs on
    /// to the screen's bottom on a page too short to reach it.
    private func facts(screen: CGSize) -> some View {
        HStack(alignment: .top, spacing: Metrics.columnSpacing) {
            ForEach(viewModel.columns) { column in
                Button { panel = .column(column) } label: {
                    MediaDetailFactsColumnView(column: column)
                }
                .buttonStyle(FactsButtonStyle())
                .focused($focus, equals: .column(column.id))
            }
        }
        .padding(.horizontal, Metrics.margin - Metrics.factsInset)
        .padding(.top, Metrics.factsTopPadding)
        .padding(.bottom, Metrics.factsBottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Metrics.factsBand)
        // Below the band, past the page's end unless the page is shorter than the screen.
        .background(alignment: .bottom) {
            Metrics.factsBandEnd
                .frame(height: screen.height)
                .offset(y: screen.height)
        }
        .focusSection()
    }

    // MARK: Similar items

    /// A similar item's card grown to full screen over the page, with its actions.
    private var expandedSimilarItem: some View {
        GeometryReader { proxy in
            if let card = expansion.card {
                MediaCardExpansionView(
                    viewModel: expansion,
                    card: card,
                    globalFrame: proxy.frame(in: .global),
                    focus: $focus,
                    actionsFocus: .expanded(card.item.id),
                    onPlay: { onPlay($0, $1, nil) }
                )
                // It appears exactly on top of its poster, so it must not fade in.
                .transition(.identity)
                .onAppear {
                    expansion.grow { [focus = $focus] in
                        Task { @MainActor in focus.wrappedValue = .expanded(card.item.id) }
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Moving

    /// Where focus is: on the card's actions, in the sections, or nowhere on the page.
    private var area: Area? {
        if focusedAction != nil { return .card }
        return focus == nil || focus == .actions ? nil : .sections
    }

    /// The first thing in the sections focus can go to: on a show's page or an episode's, where the user
    /// is in the show.
    private var firstSection: MediaDetailFocus? {
        if let episode = viewModel.startingEpisodeID { return .episode(episode) }
        if let person = viewModel.people.first { return .person(person.id) }
        if let similar = viewModel.similar.first { return .similar(similar.item.id) }
        if viewModel.overview != nil { return .overview }
        return viewModel.columns.first.map { .column($0.id) }
    }

    /// The facts' first column, where Information goes.
    private var factsFocus: MediaDetailFocus? {
        viewModel.columns.first.map { .column($0.id) }
    }

    /// Moves focus on to the sections, once: to the first row, or all the way down to the facts.
    private func enterSections() {
        guard !hasEnteredSections, let first = destination == .facts ? factsFocus ?? firstSection : firstSection else { return }
        hasEnteredSections = true
        isEntering = true
        focus = first
    }

    /// Back closes a panel, shrinks a similar item's card back onto its poster, or scrolls back up to
    /// the card, which then takes over.
    private func back() {
        if let panel {
            close(panel)
        } else if let item = expansion.item {
            expansion.collapse { [focus = $focus] in focus.wrappedValue = .similar(item) }
        } else if scroll.progress == 0 {
            onClose(focusedAction)
        } else {
            focus = .actions
        }
    }

    /// Closes `panel`, focus staying on what opened it.
    private func close(_ panel: MediaDetailPanel) {
        self.panel = nil
        focus = panel.opener
    }
}

/// What has focus on an item's page.
enum MediaDetailFocus: Hashable {
    /// The card's actions, at the top.
    case actions
    /// A season's tab, by its number.
    case season(Int)
    /// An episode's still, which plays it.
    case episode(MediaItem.ID)
    /// An episode's text, which opens its page.
    case episodeInfo(MediaItem.ID)
    case person(String)
    case similar(MediaItem.ID)
    /// A similar item's card's actions, once it's full screen.
    case expanded(MediaItem.ID)
    case overview
    case rating(String)
    case column(String)
}

extension MediaDetailPageView {
    /// How far the card has scrolled away, from 0 at the top to 1 once it's gone.
    @MainActor
    @Observable
    final class Scroll {
        var progress = 0.0
    }

    /// The card's backdrop, which stays where it is: as the card scrolls away, its scrim gives way to the
    /// system's material over it, and a gray wash. A material blurs the art as it is, at full size: the
    /// art fetched tiny and blown up looked blocky behind the facts.
    struct Backdrop: View {
        let card: MediaCardViewModel
        let scroll: Scroll
        let screen: CGSize
        @Environment(\.hidesSpoilers) private var hidesSpoilers

        var body: some View {
            let progress = scroll.progress
            let spoilerBlur = card.isSpoiler(hidingSpoilers: hidesSpoilers) ? MediaCardView.Metrics.spoilerBlur : 0
            ZStack {
                Color.black
                RemoteImageView(url: card.landscapeArtworkURL, priority: .high) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .blur(radius: spoilerBlur, opaque: true)
                } placeholder: {
                    Color.clear
                }
                .frame(width: screen.width, height: screen.height)
                .clipped()
                MediaCardView.detailsScrim
                    .opacity(1 - progress)
                Rectangle()
                    .fill(Metrics.material)
                    .opacity(progress)
                Metrics.wash
                    .opacity(progress)
            }
            .frame(width: screen.width, height: screen.height)
            .accessibilityHidden(true)
        }
    }

    /// The item's logo, or its title without one, centered at the top of the sections, arriving as the
    /// card scrolls away.
    struct Logo: View {
        let viewModel: MediaDetailViewModel
        let scroll: Scroll

        var body: some View {
            Group {
                if let url = viewModel.card.logoArtworkURL {
                    RemoteImageView(url: url) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        Color.clear
                    }
                    .frame(width: Metrics.logoSize.width, height: Metrics.logoSize.height)
                    .accessibilityLabel(viewModel.item.name)
                } else {
                    Text(viewModel.item.name)
                        .font(.title2)
                        .bold()
                }
            }
            .opacity(scroll.progress)
        }
    }

    /// Where on the page something is: on the card at the top, or in the sections below, whose end is
    /// the facts, where Information scrolls all the way down to.
    enum Area: Hashable {
        case card
        case sections
    }

    /// A tile in About: the system's resting platter, lifting and brightening with focus.
    struct TileButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            Tile(configuration: configuration)
        }

        struct Tile: View {
            let configuration: Configuration
            @Environment(\.isFocused) private var isFocused

            var body: some View {
                configuration.label
                    .padding(Metrics.tilePadding)
                    .background(.white.opacity(isFocused ? Metrics.focusedTileOpacity : Metrics.tileOpacity), in: .rect(cornerRadius: Metrics.tileCornerRadius))
                    .scaleEffect(isFocused ? Metrics.focusedScale : 1)
                    .shadow(color: .black.opacity(isFocused ? Metrics.focusedShadowOpacity : 0), radius: Metrics.focusedShadowRadius, y: Metrics.focusedShadowOffset)
                    .animation(Metrics.focusMotion, value: isFocused)
            }
        }
    }

    /// A column of facts: no platter until it has focus, as the TV app's.
    struct FactsButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            Column(configuration: configuration)
        }

        struct Column: View {
            let configuration: Configuration
            @Environment(\.isFocused) private var isFocused

            var body: some View {
                configuration.label
                    .padding(Metrics.factsInset)
                    .background(.white.opacity(isFocused ? Metrics.tileOpacity : 0), in: .rect(cornerRadius: Metrics.tileCornerRadius))
                    .scaleEffect(isFocused ? Metrics.focusedScale : 1)
                    .animation(Metrics.focusMotion, value: isFocused)
            }
        }
    }
}

private extension CGSize {
    static func * (size: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: size.width * scale, height: size.height * scale)
    }
}
