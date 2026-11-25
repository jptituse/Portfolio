import PortfolioSharedPlaybackEngine

/// One of the player's menus, as the system player's are: sections, each under a header if it has one,
/// of choices, toggles and submenus. A submenu opens in its menu's place, under its title.
public struct PlayerMenu: Identifiable {
    /// Unique among the player's menus and their submenus.
    public let id: String
    /// What it's called: the header a submenu opens under.
    public let title: String
    public let sections: [Section]

    public struct Section: Identifiable {
        public let id: String
        public let header: String?
        public let items: [Item]
    }

    public struct Item: Identifiable {
        public enum Kind {
            /// One of a section's choices, checked when it's the one chosen. Choosing it closes the menu.
            case choice(isChosen: Bool)
            /// On or off, checked while on. The menu stays open.
            case toggle(isOn: Bool)
            /// Opens a submenu in the menu's place.
            case submenu(PlayerMenu)
        }

        /// Unique within its menu.
        public let id: String
        public let title: String
        /// What's chosen in a submenu, under its title.
        public let detail: String?
        public let kind: Kind
        /// How subtitles would look with this chosen, to show while it has focus.
        public let captionStyle: CaptionStyle?
        let action: @MainActor () -> Void

        init(id: String, title: String, detail: String? = nil, kind: Kind, captionStyle: CaptionStyle? = nil, action: @escaping @MainActor () -> Void = {}) {
            self.id = id
            self.title = title
            self.detail = detail
            self.kind = kind
            self.captionStyle = captionStyle
            self.action = action
        }

        /// Whether it shows a check.
        public var isChecked: Bool {
            switch kind {
            case .choice(let isChosen): isChosen
            case .toggle(let isOn): isOn
            case .submenu: false
            }
        }

        public var submenu: PlayerMenu? {
            if case .submenu(let menu) = kind { menu } else { nil }
        }
    }

    /// The item focus starts on as it opens: as a submenu, the one chosen, else the first.
    func firstFocus(asSubmenu: Bool) -> Item.ID? {
        let items = sections.flatMap(\.items)
        if asSubmenu, let chosen = items.first(where: \.isChecked) { return chosen.id }
        return items.first?.id
    }
}
