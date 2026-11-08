import Observation
import SwiftUI

/// Which section is on screen and whether the sidebar is showing.
@MainActor
@Observable
final class MainNavigationViewModel {
    /// Starts hidden, so the app opens with focus on the content rather than on the sidebar.
    var columnVisibility: NavigationSplitViewVisibility = .detailOnly

    /// The section chosen in the sidebar.
    var selection: MainSection? = .home {
        didSet {
            if let selection { openedSections.insert(selection) }
        }
    }

    private var openedSections: Set<MainSection> = [.home]

    /// The sections to keep alive: each one opened so far, so moving between them keeps your place.
    var sectionsToKeep: [MainSection] {
        MainSection.allCases.filter(openedSections.contains)
    }
}
