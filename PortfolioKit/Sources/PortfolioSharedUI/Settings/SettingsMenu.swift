import Foundation
import PortfolioShared

/// A menu in Settings: its rows under their headers, and the icon and description shown beside it.
/// `SettingsViewModel` builds each as it is now, so its values are always current.
public struct SettingsMenu: Identifiable {
    public let id: ID
    public let title: String
    /// What's drawn large beside the menu.
    public let tile: Tile
    /// What the menu is for, shown beside it while no row with a description of its own has focus.
    public let summary: String?
    public let sections: [Section]

    init(id: ID, title: String, tile: Tile, summary: String? = nil, sections: [Section]) {
        self.id = id
        self.title = title
        self.tile = tile
        self.summary = summary
        self.sections = sections
    }

    /// What's drawn large beside a menu, or beside a row with focus that has one of its own. Each is
    /// drawn as it is, fitted to the same largest size: a symbol on its own, as the system draws them,
    /// with nothing behind it.
    public enum Tile: Hashable {
        case symbol(String)
        /// An image, such as a server's icon or someone's picture, once it's loaded, else the symbol.
        case image(URL?, placeholder: String)
        /// One of the pictures someone can choose.
        case profilePicture(ProfilePicture)
    }

    /// Every row, in order.
    public var rows: [Row] { sections.flatMap(\.rows) }

    public func row(_ id: Row.ID) -> Row? {
        rows.first { $0.id == id }
    }

    /// Whether any row can be selected. Without one, its rows that only show something take focus, so
    /// there's somewhere for focus to be.
    public var hasSelectableRows: Bool {
        rows.contains { $0.select != nil }
    }

    /// Settings' menus, each a place in it.
    public enum ID: Hashable, Sendable {
        case root
        case appearance, hero, heroCollection, heroPlaylist, topShelf
        case video, dolbyVisionFEL
        case audio, objectAudio, audioDelay
        case playback, minimumQuality, maximumQuality, audioLanguage, subtitleLanguage, skipForward, skipBack
        case segment(MediaSegmentKind), credits
        case servers, server(MediaServer.ID)
        case accounts, profile(ProfileID), account(ProfileID), picture(ProfileID)
        case services
        case about
    }

    public struct Section: Identifiable {
        public let id: String
        public let header: String?
        public let rows: [Row]

        init(id: String, header: String? = nil, rows: [Row]) {
            self.id = id
            self.header = header
            self.rows = rows
        }
    }

    /// A row of a menu: its title, the value it has now, and what selecting it does.
    public struct Row: Identifiable {
        public let id: String
        public let title: String
        /// What it's set to, at its trailing end, such as "On" or "7.1.4".
        public let value: String?
        /// What it does, shown beside the menu while it has focus.
        public let description: String?
        /// What's drawn beside the menu while it has focus, in place of the menu's own, such as a
        /// picture someone could choose.
        public let tile: Tile?
        public let kind: Kind
        /// What selecting it does. Nil for a row that only shows something.
        public let select: (() -> Void)?

        init(id: String, title: String, value: String? = nil, description: String? = nil, tile: Tile? = nil, kind: Kind = .action, select: (() -> Void)? = nil) {
            self.id = id
            self.title = title
            self.value = value
            self.description = description
            self.tile = tile
            self.kind = kind
            self.select = select
        }

        /// How a row looks, and what selecting it is like.
        public enum Kind {
            /// Opens a menu of its own: drawn with a chevron.
            case submenu
            /// Changes its value in place, such as turning something on or off.
            case setting
            /// One of a menu's choices, checked if it's the one chosen. Choosing goes back.
            case choice(isChosen: Bool)
            /// Does something, such as testing a server's speed.
            case action
            /// Does something that can't be undone, such as removing a server: drawn in red.
            case destructive
            /// Shows a value, and can't be selected.
            case info
            /// Edits its value as text, such as a server's address: drawn with a chevron.
            case text
        }
    }
}
