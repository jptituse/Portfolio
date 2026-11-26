import PortfolioSharedUI
import SwiftUI

/// One of Settings' menus: its rows under their headers, as the system's Settings app lists them. A
/// row that opens a menu has a chevron, a choice made is checked, and a row's value sits at its
/// trailing end. It scrolls where it's taller than fits.
struct SettingsMenuView: View {
    let menu: SettingsMenu
    var focus: FocusState<SettingsView.Focus?>.Binding

    var body: some View {
        List {
            ForEach(menu.sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        SettingsRowView(row: row, isFocusableInfo: !menu.hasSelectableRows)
                            .focused(focus, equals: SettingsView.Focus(menu: menu.id, row: row.id))
                            .accessibilityIdentifier("settings.\(row.id)")
                    }
                } header: {
                    if let header = section.header {
                        Text(header)
                            .font(Metrics.headerFont)
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                            .padding(.top, Metrics.headerTopPadding)
                            .padding(.bottom, Metrics.headerBottomPadding)
                            .padding(.leading, SettingsRowView.Metrics.inset)
                    }
                }
            }
        }
        .scrollClipDisabled()
    }
}

extension SettingsMenuView {
    struct Metrics {
        /// As the system's Settings app heads its sections: small, gray capitals, well below the
        /// section before.
        static let headerFont = Font.caption.weight(.bold)
        static let headerTopPadding: CGFloat = 30
        static let headerBottomPadding: CGFloat = 10
    }
}
