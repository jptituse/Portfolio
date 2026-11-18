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
    /// What's playing, while something is.
    @State private var player: PlayerViewModel?
    /// Shows what's playing's detail view behind the player as it closes, when it didn't open from there.
    @State private var showDetailsOnClose: (() -> Void)?
    /// Whether the player is up, from Play until it has gone.
    @State private var isPlayerUp = false
    @FocusState private var focusedSection: MainSection?

    init(currentProfile: CurrentProfileViewModel, makePlaybackEngine: @escaping () throws -> any PlaybackEngine) {
        self.currentProfile = currentProfile
        self.makePlaybackEngine = makePlaybackEngine
        _viewModel = State(initialValue: MainNavigationViewModel(libraries: currentProfile.makeLibrariesViewModel()))
        _home = State(initialValue: currentProfile.makeHomeViewModel())
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
                        .disabled(!isShowing)
                        .accessibilityHidden(!isShowing)
                }
            }
        }
        .environment(\.isPlayerUp, isPlayerUp)
        .environment(\.preparePlayback, PreparePlaybackAction(currentProfile))
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

    /// Plays `item` from `position`, full screen, from the profile's server. `showDetails`, if given,
    /// shows its detail view behind the player as it closes.
    private func play(_ item: MediaItem, from position: Duration, showDetails: (() -> Void)?) {
        showDetailsOnClose = showDetails
        isPlayerUp = true
        player = currentProfile.makePlayer(for: item, startingAt: position, makeEngine: makePlaybackEngine)
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
        case .search: SearchView()
        case .settings: SettingsView()
        }
    }
}

extension MainNavigationView {
    struct Metrics {
        /// Room between the rows' highlights, as in the Apple TV app's sidebar.
        static let rowSpacing: CGFloat = 10
        static let separatorHeight: CGFloat = 2
        static let separatorInset: CGFloat = 20
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
    MainNavigationView(currentProfile: .preview()) { throw CancellationError() }
}
#endif
