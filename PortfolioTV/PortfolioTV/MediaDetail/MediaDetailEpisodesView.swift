import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// A show's seasons and episodes, at the top of its page or an episode's, as the TV app's: a tab for
/// each season, then every episode in one row, season after season, starting where the user is in the
/// show (`MediaDetailViewModel.startingEpisodeID`). Moving along the row selects the season it's in,
/// and a season's tab taking focus scrolls the row to its first episode. Up and Down between them land
/// on the season selected and the episode focus was on last in it, else its first: on its still from
/// the tabs, and on its text from the sections below. An episode's still plays it, and its text opens
/// its page (`MediaDetailEpisodeView`).
struct MediaDetailEpisodesView: View {
    let viewModel: MediaDetailViewModel
    var focus: FocusState<MediaDetailFocus?>.Binding
    let onPlay: (MediaCardViewModel) -> Void
    let onOpen: (MediaCardViewModel) -> Void

    /// The season whose tab is selected, once focus has been among the seasons or episodes.
    @State private var selectedSeason: Int?
    /// The episode focus was on last.
    @State private var lastEpisode: MediaItem.ID?
    /// Whether focus coming into the row lands on an episode's text, as it does from below, rather than
    /// its still, as from the tabs.
    @State private var landsOnText = false

    var body: some View {
        let seasons = viewModel.seasons
        let selected = selectedSeason ?? startingSeason
        ScrollViewReader { reader in
            VStack(alignment: .leading, spacing: Metrics.tabsSpacing) {
                HStack(spacing: Metrics.tabSpacing) {
                    ForEach(seasons) { season in
                        Button(season.name) {
                            focus.wrappedValue = .episode(firstEpisode(in: season))
                        }
                        .buttonStyle(TabButtonStyle(isSelected: season.id == selected))
                        .focused(focus, equals: .season(season.id))
                    }
                }
                .padding(.horizontal, Metrics.margin)
                .focusSection()
                .defaultFocus(focus, selected.map { .season($0) }, priority: .userInitiated)

                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: Metrics.episodeSpacing) {
                        ForEach(viewModel.episodes, id: \.item.id) { card in
                            MediaDetailEpisodeView(card: card, focus: focus) {
                                onPlay(card)
                            } onOpen: {
                                onOpen(card)
                            }
                            .id(card.item.id)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .contentMargins(.horizontal, Metrics.margin, for: .scrollContent)
                .focusSection()
                .defaultFocus(focus, episode(in: selected, of: seasons).map { landsOnText ? .episodeInfo($0) : .episode($0) }, priority: .userInitiated)
            }
            // Where the user is in the show, as soon as the episodes are in.
            .onChange(of: viewModel.startingEpisodeID, initial: true) { _, start in
                if let start { reader.scrollTo(start, anchor: .leading) }
            }
            .onChange(of: focus.wrappedValue) { _, focused in
                switch focused {
                case .season(let season):
                    selectedSeason = season
                    landsOnText = false
                    if let season = seasons.first(where: { $0.id == season }) {
                        withAnimation(Metrics.scroll) { reader.scrollTo(firstEpisode(in: season), anchor: .leading) }
                    }
                case .episode(let id), .episodeInfo(let id):
                    lastEpisode = id
                    if let card = viewModel.episodes.first(where: { $0.item.id == id }) {
                        selectedSeason = MediaDetailViewModel.seasonNumber(of: card.item)
                    }
                case .actions, nil:
                    break
                default:
                    // In the sections below.
                    landsOnText = true
                }
            }
        }
    }

    /// The season the row starts in.
    private var startingSeason: Int? {
        let start = viewModel.episodes.first { $0.item.id == viewModel.startingEpisodeID }
        return start.map { MediaDetailViewModel.seasonNumber(of: $0.item) }
    }

    /// Where focus coming into the row lands in `season`: the episode focus was on last, if it's in it,
    /// else where the row starts, if that is, else the season's first.
    private func episode(in season: Int?, of seasons: [MediaDetailViewModel.Season]) -> MediaItem.ID? {
        for id in [lastEpisode, viewModel.startingEpisodeID].compactMap({ $0 }) {
            if let card = viewModel.episodes.first(where: { $0.item.id == id }), MediaDetailViewModel.seasonNumber(of: card.item) == season {
                return id
            }
        }
        return seasons.first { $0.id == season }?.firstEpisodeID
    }

    /// The episode a season's tab goes to.
    private func firstEpisode(in season: MediaDetailViewModel.Season) -> MediaItem.ID {
        episode(in: season.id, of: [season]) ?? season.firstEpisodeID
    }
}

extension MediaDetailEpisodesView {
    /// A season's tab: plain text, on a gray capsule while it's selected, black on white with focus.
    struct TabButtonStyle: ButtonStyle {
        let isSelected: Bool

        func makeBody(configuration: Configuration) -> some View {
            Tab(configuration: configuration, isSelected: isSelected)
        }

        struct Tab: View {
            let configuration: Configuration
            let isSelected: Bool
            @Environment(\.isFocused) private var isFocused

            var body: some View {
                configuration.label
                    .font(.callout.weight(.medium))
                    .foregroundStyle(isFocused ? .black : .white.opacity(isSelected ? 1 : Metrics.unselectedOpacity))
                    .padding(.horizontal, Metrics.tabHorizontalPadding)
                    .padding(.vertical, Metrics.tabVerticalPadding)
                    .background(
                        Capsule().fill(.white.opacity(isFocused ? 1 : isSelected ? Metrics.selectedOpacity : 0))
                    )
                    .scaleEffect(isFocused ? Metrics.focusedScale : 1)
                    .animation(MediaDetailEpisodeView.Metrics.focusMotion, value: isFocused)
            }
        }
    }

    /// Measured from the TV app's show page at 1080p.
    struct Metrics {
        static var margin: CGFloat { MediaDetailPageView.Metrics.margin }
        static let tabsSpacing: CGFloat = 20
        static let tabSpacing: CGFloat = 8
        static let tabHorizontalPadding: CGFloat = 30
        static let tabVerticalPadding: CGFloat = 12
        static let selectedOpacity = 0.2
        static let unselectedOpacity = 0.6
        static let focusedScale: CGFloat = 1.05
        static let episodeSpacing: CGFloat = 40
        static var scroll: Animation { .smooth(duration: 0.35) }
    }
}
