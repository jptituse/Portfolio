import Observation
import PortfolioSharedUI
import SwiftUI

/// The sidebar's sections, which one is on screen, and whether the sidebar is showing.
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
}
