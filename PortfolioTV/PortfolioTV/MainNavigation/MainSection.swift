import Foundation
import PortfolioShared
import PortfolioSharedUI

/// A top-level section of the app: Search, Home, a library, or Settings.
enum MainSection: Hashable {
    case search
    case home
    case library(LibraryScope)
    case settings

    var title: String {
        switch self {
        case .search: String(localized: "Search")
        case .home: String(localized: "Home")
        case .library(let scope): scope.title
        case .settings: String(localized: "Settings")
        }
    }

    var systemImage: String {
        switch self {
        case .search: "magnifyingglass"
        case .home: "house"
        case .library(let scope): scope.systemImage
        case .settings: "gearshape"
        }
    }
}
