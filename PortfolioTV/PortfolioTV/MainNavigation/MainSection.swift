import SwiftUI

/// The top-level sections, in sidebar order. Search comes first, as in the Apple TV app, but the app
/// opens on Home.
enum MainSection: Hashable, CaseIterable {
    case search
    case home
    case libraries
    case settings

    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .libraries: "Libraries"
        case .search: "Search"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .libraries: "rectangle.stack"
        case .search: "magnifyingglass"
        case .settings: "gearshape"
        }
    }
}
