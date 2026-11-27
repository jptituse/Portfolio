import PortfolioShared
import PortfolioSharedPlaybackEngine
import PortfolioSharedUI
import SwiftUI

/// The open profile's app: a full-height sidebar, with the profile at the top and the top-level
/// sections below, over the section on screen. The profile's libraries join the sidebar once they've
/// loaded: one entry per standard kind, then, below a separator, libraries on their own and Settings. The app opens with the sidebar hidden and focus on the
/// content. Left or Menu brings the sidebar in over the content, and moving back into the content
/// dismisses it. Each section has its own navigation stack, so moving between sections keeps your
/// place in each. Play anywhere plays full screen over all of it.
struct MainNavigationView: View {
    let currentProfile: CurrentProfileViewModel
    /// Makes the engine each player plays in, of the app's choosing.
    let makePlaybackEngine: () throws -> any PlaybackEngine

    @State private var viewModel: MainNavigationViewModel
    @State private var home: HomeViewModel
    @State private var search: SearchViewModel
    @State private var settings: SettingsViewModel
    /// What's playing, while something is.
    @State private var player: PlayerViewModel?
    /// Shows what's playing's detail view behind the player as it closes, when it didn't open from there.
    @State private var showDetailsOnClose: (() -> Void)?
    /// Whether Play on a show is waiting for the server to say which episode is next, so a second press
    /// doesn't play it twice.
    @State private var isFindingEpisode = false
    /// Whether the player is up, from Play until it has gone.
    @State private var isPlayerUp = false
    @FocusState private var focusedSection: MainSection?

    /// - Parameter playbackEngine: the playback engine's name and version, for Settings' About.
    init(
        currentProfile: CurrentProfileViewModel,
        playbackEngine: (name: String, version: String),
        makePlaybackEngine: @escaping () throws -> any PlaybackEngine
    ) {
        self.currentProfile = currentProfile
        self.makePlaybackEngine = makePlaybackEngine
        _viewModel = State(initialValue: MainNavigationViewModel(libraries: currentProfile.makeLibrariesViewModel()))
        _home = State(initialValue: currentProfile.makeHomeViewModel())
        _search = State(initialValue: currentProfile.makeSearchViewModel())
        _settings = State(initialValue: currentProfile.makeSettingsViewModel(engine: playbackEngine))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $viewModel.columnVisibility) {
            List(selection: $viewModel.selection) {
                Section {
                    rows(for: viewModel.mainSections)
                } header: {
                    // A header rather than a row of its own: rows of a sidebar with a selection only
                    // take focus as navigation links.
                    CurrentProfileView(viewModel: currentProfile)
                }
                Section {
                    rows(for: viewModel.otherSections)
                } header: {
                    // The separator between the standard kinds and everything else.
                    Rectangle()
                        .fill(.separator)
                        .frame(height: Metrics.separatorHeight)
                        .padding(.horizontal, Metrics.separatorInset)
                        .accessibilityHidden(true)
                }
            }
            .sidebarRowSpacing(Metrics.rowSpacing)
            // Coming into the sidebar lands on the current section, not its first row.
            .defaultFocus($focusedSection, viewModel.selection, priority: .userInitiated)
            .task { await viewModel.libraries.load() }
        } detail: {
            ZStack {
                ForEach(viewModel.sectionsToKeep, id: \.self) { section in
                    let isShowing = section == viewModel.selection
                    NavigationStack {
                        view(for: section, isShowing: isShowing)
                            // Fades as one image as a view is pushed over it or popped off. Faded layer
                            // by layer, what's covered showed through: a full-screen card's poster under
                            // its backdrop, and the rows behind the card. It costs nothing at rest.
                            .compositingGroup()
                    }
                        .opacity(isShowing ? 1 : 0)
                        // Under an item's page, too, which takes focus and Back.
                        .disabled(!isShowing || viewModel.showsDetailPage)
                        .accessibilityHidden(!isShowing || viewModel.showsDetailPage)
                }
                // Each opens over the full-screen card it grows out of, looking just like it. The last may
                // be built ahead, until the card's Information or Down reveals it: it waits off screen, not
                // faded out, as a view that starts out transparent never takes focus, even once it shows.
                let top = viewModel.detailPages.last(where: \.isRevealed)?.id
                ForEach(viewModel.detailPages) { page in
                    MediaDetailPageView(
                        viewModel: page.viewModel,
                        isRevealed: page.isRevealed,
                        destination: page.destination,
                        openedFrom: page.openedFrom,
                        onPlay: play
                    ) { action in
                        viewModel.closeDetails(page.id, focusing: action)
                    }
                    .offset(x: page.isRevealed || page.isLeaving ? 0 : Metrics.offScreen)
                    .opacity(page.opacity)
                    .disabled(page.id != top)
                    .accessibilityHidden(page.id != top)
                    .transition(.identity)
                }
            }
        }
        .environment(\.isPlayerUp, isPlayerUp)
        .environment(\.hidesSpoilers, currentProfile.preferences?.hidesSpoilers ?? false)
        .environment(\.preparePlayback, PreparePlaybackAction(currentProfile))
        .environment(\.detailPages, DetailPagesAction(navigation: viewModel, profile: currentProfile))
        .environment(\.prepareDetails, PrepareDetailsAction(currentProfile))
        .environment(\.profilePreferences, currentProfile.preferences)
        .fullScreenCover(item: $player, onDismiss: playerDidClose) { player in
            PlayerView(viewModel: player, onClose: closePlayer)
        }
        #if DEBUG
        .onAppear(perform: playTestVideoIfAsked)
        #endif
    }

    #if DEBUG
    /// UI tests pass a test video's URL to play, so they can check playback without a server. The app
    /// itself only ever plays what its server sends.
    private func playTestVideoIfAsked() {
        guard player == nil,
            let address = ProcessInfo.processInfo.environment["PORTFOLIO_PLAYBACK_TEST_URL"],
            let url = URL(string: address) else {
            return
        }
        let title = url.deletingPathExtension().lastPathComponent
        isPlayerUp = true
        player = PlayerViewModel(title: title, source: PlaybackSource(url: url), makeEngine: makePlaybackEngine)
    }
    #endif

    private func rows(for sections: [MainSection]) -> some View {
        ForEach(sections, id: \.self) { section in
            NavigationLink(value: section) {
                Label(section.title, systemImage: section.systemImage)
            }
            .focused($focusedSection, equals: section)
        }
    }

    /// Plays `item` full screen, from the profile's server, from the beginning or resuming. A show plays
    /// its next episode (`CurrentProfileViewModel.nextEpisode(ofShow:)`), once the server has said which,
    /// resuming it if the user is partway through. `showDetails`, if given, shows its detail view behind
    /// the player as it closes.
    private func play(_ item: MediaItem, from start: PlaybackStart, showDetails: (() -> Void)?) {
        guard item.kind == .series else {
            present(item, from: start, showDetails: showDetails)
            return
        }
        guard !isFindingEpisode else { return }
        isFindingEpisode = true
        Task {
            let next = await currentProfile.nextEpisode(ofShow: item)
            isFindingEpisode = false
            if let next { present(next.episode, from: next.start, showDetails: showDetails) }
        }
    }

    private func present(_ item: MediaItem, from start: PlaybackStart, showDetails: (() -> Void)?) {
        showDetailsOnClose = showDetails
        isPlayerUp = true
        player = currentProfile.makePlayer(for: item, from: start, makeEngine: makePlaybackEngine)
    }

    /// Closes the player, and has what played show its detail view behind it as it goes, so it's there
    /// as the player fades away.
    private func closePlayer() {
        player = nil
        showDetailsOfWhatPlayed()
    }

    /// The player has gone: what's behind it can take focus again. Closed some other way than
    /// `closePlayer()`, what played still shows its detail view.
    private func playerDidClose() {
        showDetailsOfWhatPlayed()
        isPlayerUp = false
    }

    /// Shows what played's detail view, once.
    private func showDetailsOfWhatPlayed() {
        let showDetails = showDetailsOnClose
        showDetailsOnClose = nil
        showDetails?()
    }

    /// A section's view. Sections that load from the server load again each time they're shown.
    @ViewBuilder private func view(for section: MainSection, isShowing: Bool) -> some View {
        switch section {
        case .home: HomeView(viewModel: home, isShowing: isShowing, onPlay: play)
        case .library(let scope): LibraryView(viewModel: viewModel.libraries.viewModel(for: scope), isShowing: isShowing, onPlay: play)
        case .search: SearchView(viewModel: search, onPlay: play)
        case .settings: SettingsView(viewModel: settings)
        }
    }
}

extension MainNavigationView {
    struct Metrics {
        /// Room between the rows' highlights, as in the Apple TV app's sidebar.
        static let rowSpacing: CGFloat = 10
        static let separatorHeight: CGFloat = 2
        static let separatorInset: CGFloat = 20
        /// Where an item's page waits, built ahead: past the right of any screen.
        static let offScreen: CGFloat = 10_000
    }
}

private extension View {
    /// Spaces the sidebar's rows apart. Lists can only do this from tvOS 27; earlier, the rows touch.
    @ViewBuilder func sidebarRowSpacing(_ spacing: CGFloat) -> some View {
        if #available(tvOS 27, *) {
            listRowSpacing(spacing)
        } else {
            self
        }
    }
}

#if DEBUG
#Preview {
    MainNavigationView(currentProfile: .preview(), playbackEngine: ("AetherEngine", "1.0")) { throw CancellationError() }
}
#endif
