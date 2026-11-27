import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// Search: the system's keyboard, with dictation and suggestions of what was found, then what the
/// profile's server has that matches what's typed (`SearchViewModel`), updating as it's typed. Once
/// something's typed, a row of filters, styled as a library's sidebar items, leads the results: Top
/// Results, each kind, then the server's genres. Top Results is a grid of movies, shows, music videos
/// and collections, with the episodes and people found in rows below; a kind's or a genre's filter is
/// a grid of its own. Selecting a poster grows it straight into the item's full-screen card, as a
/// library's does, and Back shrinks it back onto the poster.
///
/// With the one-line keyboard, the keyboard scrolls away as focus goes down into the results. With the
/// grid keyboard, the system puts the results beside it, where they stay within their bounds, so they
/// never slide under the keyboard or up past the divider below the suggestions. Apple keeps hiding the
/// grid keyboard for its own apps.
struct SearchView: View {
    @Bindable var viewModel: SearchViewModel
    /// Plays an item, from the beginning or resuming.
    let onPlay: PlayAction

    @Environment(\.displayScale) private var displayScale
    @FocusState private var focus: SearchFocus?
    @State private var expansion = MediaCardExpansionViewModel()
    /// Whether the system put the results beside the grid keyboard, rather than under the one-line one.
    @State private var isBesideKeyboard = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                if viewModel.showsFilters {
                    filters
                }
                if let message {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
                if viewModel.resultsFilter == .people {
                    peopleGrid
                } else if !viewModel.items.isEmpty {
                    itemGrid
                }
                if !viewModel.episodes.isEmpty {
                    row(viewModel.title(of: .episodes)) {
                        ForEach(viewModel.episodes) { poster(viewModel.card(for: $0)) }
                    }
                }
                if viewModel.resultsFilter == .topResults, !viewModel.people.isEmpty {
                    row(viewModel.title(of: .people)) {
                        ForEach(viewModel.people, content: person)
                    }
                }
            }
            .padding(.bottom, Metrics.bottomPadding)
        }
        // Beside the grid keyboard, within the results' own bounds, with room for a focused poster's lift.
        .scrollClipDisabled(!isBesideKeyboard)
        .contentMargins([.top, .leading], isBesideKeyboard ? Metrics.liftRoom : 0, for: .scrollContent)
        .padding([.top, .leading], isBesideKeyboard ? -Metrics.liftRoom : 0)
        .onGeometryChange(for: Bool.self) { $0.frame(in: .global).minX > Metrics.besideKeyboardMinX } action: { isBesideKeyboard = $0 }
        .searchable(text: $viewModel.text, prompt: Text("Movies, Shows, People and More"))
        .searchSuggestions {
            ForEach(viewModel.suggestions, id: \.self) { name in
                Text(name).searchCompletion(name)
            }
        }
        .disabled(expansion.blocksFocus)
        .overlay { expandedCard }
        // The full-screen card's artwork fills the screen, so it's fetched at the screen's size.
        .onGeometryChange(for: CGSize.self, of: \.screenSize) { screen in
            viewModel.setArtworkSizes(
                poster: Metrics.posterSize,
                still: Metrics.stillSize,
                screen: screen,
                logo: MediaCardView.Metrics.detailsLogoSize,
                scale: displayScale
            )
        }
        .onChange(of: focus) { old, focus in
            switch focus {
            case .filter(let filter):
                // Coming into the row lands on the filter chosen: from the keyboard, tvOS put focus on the
                // nearest filter, despite the row's default, which then took over the results.
                if case .filter = old {
                    viewModel.filterFocused(filter)
                } else if filter != viewModel.chosenFilter {
                    self.focus = .filter(viewModel.chosenFilter)
                }
            case .poster(let id):
                if let item = (viewModel.items + viewModel.episodes).first(where: { $0.id == id }) { viewModel.posterFocused(item) }
            case .person, .detail, nil:
                break
            }
        }
        .onExitCommand(perform: exitAction)
        .onAppear { viewModel.loadGenres() }
    }

    /// What Search says in place of results: what it finds, before anything's typed, or why it found
    /// nothing.
    private var message: String? {
        if let message = viewModel.message { return message }
        return viewModel.showsFilters ? nil : String(localized: "Search for movies, shows, episodes and people.")
    }

    // MARK: Filters

    /// Top Results, each kind, then the genres, as a library's sidebar items lie, in a row: only those
    /// with anything in them, and the one chosen. Results follow focus once it rests on one; coming into
    /// the row lands on the one chosen.
    private var filters: some View {
        let filters = viewModel.filters
        let firstGenre = filters.first { if case .genre = $0 { true } else { false } }
        return ScrollView(.horizontal) {
            HStack(spacing: Metrics.filterSpacing) {
                ForEach(filters, id: \.self) { filter in
                    if filter == firstGenre {
                        Divider()
                            .frame(height: Metrics.filterDividerHeight)
                            .padding(.horizontal, Metrics.filterSpacing)
                    }
                    Button {
                        viewModel.filterSelected(filter)
                    } label: {
                        Text(viewModel.title(of: filter))
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(LibrarySidebarView.SidebarItemButtonStyle(isShowing: filter == viewModel.chosenFilter))
                    .focused($focus, equals: .filter(filter))
                    // Marked as chosen rather than renamed, so it keeps its name for VoiceOver and tests.
                    .accessibilityAddTraits(filter == viewModel.chosenFilter ? .isSelected : [])
                    .accessibilityIdentifier("search.filter")
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .focusSection()
        .defaultFocus($focus, .filter(viewModel.chosenFilter), priority: .userInitiated)
    }

    // MARK: Results

    /// The items found, as a grid that fills the width: posters, or stills for episodes and music videos
    /// on their own.
    private var itemGrid: some View {
        let size = viewModel.gridShape == .still ? Metrics.stillSize : Metrics.posterSize
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: size.width, maximum: size.width), spacing: Metrics.itemSpacing, alignment: .top)],
            alignment: .leading,
            spacing: Metrics.gridRowSpacing
        ) {
            ForEach(viewModel.items) { poster(viewModel.card(for: $0)) }
        }
        .focusSection()
    }

    /// The people found, in People's filter.
    private var peopleGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: Metrics.pictureSize.width, maximum: Metrics.pictureSize.width), spacing: Metrics.itemSpacing, alignment: .top)],
            alignment: .leading,
            spacing: Metrics.gridRowSpacing
        ) {
            ForEach(viewModel.people, content: person)
        }
        .focusSection()
    }

    /// A titled row that scrolls sideways, below Top Results' grid.
    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Metrics.titleSpacing) {
            Text(title)
                .font(Metrics.rowTitleFont)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Metrics.itemSpacing) {
                    content()
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
        .focusSection()
    }

    /// A poster, which grows to full screen when selected, as a library's. An episode's still shows its
    /// show's logo, so what it is goes under it.
    private func poster(_ card: MediaCardViewModel) -> some View {
        let size = viewModel.shape(of: card.item) == .still ? Metrics.stillSize : Metrics.posterSize
        return VStack(alignment: .leading, spacing: Metrics.captionSpacing) {
            Button {
                expansion.select(card)
            } label: {
                MediaCardView(viewModel: card)
                    .frame(width: size.width, height: size.height)
                    .contentShape(.hoverEffect, .rect(cornerRadius: MediaCardView.Metrics.posterCornerRadius))
                    .hoverEffect(.highlight)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                        expansion.posterMoved(card.item.id, to: frame)
                    }
            }
            .buttonStyle(MediaCardButtonStyle())
            // Hidden under its card while that's open, as faint as still takes focus, for its card to
            // hand focus back to.
            .opacity(expansion.item == card.item.id ? MediaCardExpansionViewModel.hiddenPosterOpacity : 1)
            .focused($focus, equals: .poster(card.item.id))
            .environment(\.viewState, .root)
            .accessibilityIdentifier("search.poster")
            .accessibilityLabel(card.item.name)
            if let caption = viewModel.caption(of: card.item) {
                VStack(alignment: .leading, spacing: Metrics.captionLineSpacing) {
                    Text(card.item.name)
                        .font(.caption)
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .frame(width: size.width, alignment: .leading)
                .accessibilityHidden(true)
            }
        }
    }

    /// Someone found, as in an item's Cast & Crew. Selecting them does nothing until #44.
    private func person(_ person: Person) -> some View {
        MediaDetailPersonView(
            name: person.name,
            role: nil,
            pictureURL: viewModel.pictureURL(
                of: person,
                pixelSize: CGSize(width: Metrics.pictureSize.width * displayScale, height: Metrics.pictureSize.height * displayScale)
            )
        )
        .focused($focus, equals: .person(person.id))
    }

    /// A poster's card grown to full screen over everything, the keyboard too, with its actions.
    private var expandedCard: some View {
        GeometryReader { proxy in
            if let card = expansion.card {
                MediaCardExpansionView(
                    viewModel: expansion,
                    card: card,
                    globalFrame: proxy.frame(in: .global),
                    focus: $focus,
                    actionsFocus: .detail(card.item.id),
                    onPlay: { onPlay($0, $1, nil) }
                )
                // It appears exactly on top of its poster, so it must not fade in.
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

    /// What Back does: shrinks a grown card back onto its poster. Otherwise it does what it always does.
    private var exitAction: (() -> Void)? {
        guard let item = expansion.item else { return nil }
        return { [focus = $focus] in
            expansion.collapse { focus.wrappedValue = .poster(item) }
        }
    }
}

extension SearchView {
    struct Metrics {
        static let sectionSpacing: CGFloat = 50
        static let titleSpacing: CGFloat = 24
        static let itemSpacing: CGFloat = 40
        static let gridRowSpacing: CGFloat = 48
        static let filterSpacing: CGFloat = 8
        static let filterDividerHeight: CGFloat = 40
        static let bottomPadding: CGFloat = 60
        static var rowTitleFont: Font { .headline }
        /// As the item page's Related row's.
        static let posterSize = MediaDetailPageView.Metrics.posterSize
        /// As a library's grid draws a 16:9 still.
        static let stillSize = LibraryGridView.Metrics.posterSize(for: 16 / 9)
        static let pictureSize = MediaDetailPageView.Metrics.pictureSize
        static let captionSpacing: CGFloat = 16
        static let captionLineSpacing: CGFloat = 2
        /// How far past the results' bounds a focused poster's lift may draw beside the grid keyboard:
        /// short of the keyboard and the divider below the suggestions.
        static let liftRoom: CGFloat = 20
        /// Where the results start at the least beside the grid keyboard: under the one-line keyboard,
        /// they start at the screen's safe area, 80 points in.
        static let besideKeyboardMinX: CGFloat = 300
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        SearchView(viewModel: CurrentProfileViewModel.preview().makeSearchViewModel()) { _, _, _ in }
    }
}
#endif
