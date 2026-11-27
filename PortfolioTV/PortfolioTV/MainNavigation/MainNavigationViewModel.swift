import Observation
import PortfolioSharedUI
import SwiftUI

/// The sidebar's sections, which one is on screen, whether the sidebar is showing, and the item pages
/// open over the section.
///
/// The sidebar lists Search and Home, then an entry for each standard kind of library the profile
/// has (Movies, TV Shows and so on), then a separator, then libraries on their own, and Settings last.
@MainActor
@Observable
final class MainNavigationViewModel {
    /// Starts hidden, so the app opens with focus on the content rather than on the sidebar.
    var columnVisibility: NavigationSplitViewVisibility = .detailOnly

    /// The section chosen in the sidebar. Home to start, not the sidebar's first section, Search.
    var selection: MainSection? = .home {
        didSet {
            if let selection, !openedSections.contains(selection) { openedSections.append(selection) }
        }
    }

    let libraries: LibrariesViewModel

    /// The sections opened so far, in the order they were.
    private var openedSections: [MainSection] = [.home]

    init(libraries: LibrariesViewModel) {
        self.libraries = libraries
    }

    /// The sections above the separator: Search, Home, and the standard kinds of library.
    var mainSections: [MainSection] {
        [.search, .home] + libraries.standard.map(MainSection.library)
    }

    /// The sections below the separator: libraries on their own, and Settings.
    var otherSections: [MainSection] {
        libraries.special.map(MainSection.library) + [.settings]
    }

    /// The sections to keep alive: each one opened so far, so moving between them keeps your place.
    var sectionsToKeep: [MainSection] {
        openedSections
    }

    /// The item pages over the section, the one showing last: one from a full-screen card, and one more
    /// for each similar item opened from a page. The last may be built ahead and hidden, for the
    /// full-screen card showing, so Information or Down only reveals it: built as it opened, it held
    /// up the scroll.
    private(set) var detailPages: [DetailPage] = []

    /// An item page, and how to give focus back to the full-screen card it opens from.
    struct DetailPage: Identifiable {
        let viewModel: MediaDetailViewModel
        /// Whether it's showing, rather than built ahead, hidden.
        var isRevealed = false
        /// The card's action that had focus as it opened, which the page's starts on.
        var openedFrom: MediaDetailAction?
        /// Where it opened: on its first row, at its facts, or at its top, with no card under it.
        var destination = MediaDetailDestination.sections
        var returnFocus: ((MediaDetailAction?) -> Void)?
        /// How much it shows: a page with no card under it fades in and out over what's there, and stays
        /// in place as it fades out (`isLeaving`).
        var opacity = 1.0
        var isLeaving = false
        var id: MediaDetailViewModel.ID { viewModel.id }
    }

    /// Whether a page shows over the section, which then takes no focus.
    var showsDetailPage: Bool {
        detailPages.contains(where: \.isRevealed)
    }

    /// Builds the page of `card`, hidden, to open at `destination`, unless it's built already: a
    /// full-screen card's, or an episode's in its show's row. One still fading out doesn't count: it's
    /// on its way out.
    func prepareDetails(of card: MediaCardViewModel, opensAt destination: MediaDetailDestination = .sections, making makePage: () -> MediaDetailViewModel) {
        guard !detailPages.contains(where: { $0.viewModel.card === card && !$0.isLeaving }) else { return }
        // Pages built ahead for other cards; not one still fading out.
        detailPages.removeAll { !$0.isRevealed && !$0.isLeaving }
        detailPages.append(DetailPage(viewModel: makePage(), destination: destination))
    }

    /// Lets go of the page built ahead for `card`, which is no longer full screen.
    func discardDetails(of card: MediaCardViewModel) {
        detailPages.removeAll { $0.viewModel.card === card && !$0.isRevealed }
    }

    /// Shows the page of `card` over what's showing, building it if it isn't already, from the card
    /// whose actions `returnFocus` focuses.
    func openDetails(
        of card: MediaCardViewModel,
        at destination: MediaDetailDestination,
        from action: MediaDetailAction?,
        making makePage: () -> MediaDetailViewModel,
        returnFocus: @escaping (MediaDetailAction?) -> Void
    ) {
        prepareDetails(of: card, opensAt: destination, making: makePage)
        guard let index = detailPages.lastIndex(where: { $0.viewModel.card === card && !$0.isLeaving }) else { return }
        detailPages[index].isRevealed = true
        detailPages[index].openedFrom = action
        detailPages[index].destination = destination
        detailPages[index].returnFocus = returnFocus
        // With no card under it, it fades in over what's there, from as faint as still takes focus.
        if destination == .card {
            detailPages[index].opacity = Self.faintest
            let page = detailPages[index].id
            Task { @MainActor in
                withAnimation(Self.fade) { setOpacity(1, of: page) }
            }
        }
    }

    /// Hides `page`, back at its top, which its full-screen card looks just like, and gives that card's
    /// actions focus, on `action` if the page's had it. It stays built for the card's next Down.
    func closeDetails(_ page: MediaDetailViewModel.ID, focusing action: MediaDetailAction?) {
        guard let index = detailPages.firstIndex(where: { $0.id == page }) else { return }
        detailPages[index].isRevealed = false
        // In the same update, so tvOS doesn't pick something to focus itself first: it chose the card's
        // Play, which lit up for a moment on its way to the action that had focus.
        detailPages[index].returnFocus?(action)
        // With no card under it, it fades out over what's there, and goes: nothing reveals it again.
        if detailPages[index].destination == .card {
            detailPages[index].isLeaving = true
            withAnimation(Self.fade, completionCriteria: .removed) {
                setOpacity(0, of: page)
            } completion: { [weak self] in
                self?.detailPages.removeAll { $0.id == page && !$0.isRevealed }
            }
        }
    }

    private func setOpacity(_ opacity: Double, of page: MediaDetailViewModel.ID) {
        guard let index = detailPages.firstIndex(where: { $0.id == page }) else { return }
        detailPages[index].opacity = opacity
    }

    /// A page with no card under it fading in or out.
    private static var fade: Animation { .easeInOut(duration: 0.3) }
    /// The least a page shows as it fades in: one that starts out entirely transparent never takes
    /// focus.
    private static let faintest = 0.02
}
