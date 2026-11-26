import PortfolioSharedUI
import SwiftUI

/// A row of a Settings menu, drawn as the system's Settings app draws its own: on a gray platter, its
/// title, then its value at its trailing end, and a chevron if it opens a menu or asks for text, or a
/// checkmark if it's the choice made. A row that only shows a value has no platter, and can't take
/// focus, unless nothing in its menu can.
struct SettingsRowView: View {
    let row: SettingsMenu.Row
    /// Whether it takes focus though it only shows a value, because nothing else in its menu can.
    let isFocusableInfo: Bool

    var body: some View {
        if case .info = row.kind, !isFocusableInfo {
            label
        } else {
            Button(role: row.kind.isDestructive ? .destructive : nil) {
                row.select?()
            } label: {
                label
            }
            .listRowBackground(Capsule().fill(Metrics.platter))
        }
    }

    private var label: some View {
        HStack(spacing: Metrics.spacing) {
            Text(row.title)
                .lineLimit(1)
            Spacer(minLength: Metrics.spacing)
            if let value = row.value {
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            switch row.kind {
            case .submenu, .text:
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            case .choice(isChosen: true):
                Image(systemName: "checkmark")
            default:
                EmptyView()
            }
        }
        .font(Metrics.font)
        .padding(.horizontal, Metrics.inset)
    }
}

extension SettingsRowView {
    struct Metrics {
        static let spacing: CGFloat = 20
        /// Beyond a list's own inset, as far in from a row's ends as the system's text sits.
        static let inset: CGFloat = 12
        /// As the system's Settings app writes its rows: 38 points, between a list's 29 and `title3`'s 48,
        /// in medium.
        static let font = Font.headline.weight(.medium)
        /// A row at rest, as the system's: white at 10% over what's behind it.
        static let platter = Color.white.opacity(0.1)
    }
}

private extension SettingsMenu.Row.Kind {
    var isDestructive: Bool {
        if case .destructive = self { true } else { false }
    }
}
