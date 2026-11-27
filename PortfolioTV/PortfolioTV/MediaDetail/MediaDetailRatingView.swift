import PortfolioShared
import SwiftUI

/// The profile's own rating of an item, over the star among its card's actions: a row of five stars
/// that Left and Right fill in halves, with the rating beside them, then Clear Rating. Drawn as the
/// player's menus are, the system's: a glass panel, with a white capsule on the row with focus.
///
/// Across the stars lie stops focus moves along, one for no stars and one for each half star
/// (`Row.stars`), so Left, Right and swipes move it as the system moves focus, and the stars show where
/// it is. Select keeps the rating focus is on, Menu closes without changing it, and Clear Rating takes
/// it back. A single row handling Left and Right itself missed some of them, and the Select after.
struct MediaDetailRatingView: View {
    let item: MediaItem
    let preferences: ProfilePreferences
    var focus: FocusState<Row?>.Binding
    let onClose: () -> Void

    /// What has focus in the panel.
    enum Row: Hashable {
        /// A stop along the stars: none to ten halves.
        case stars(halves: Int)
        case clear
    }

    var body: some View {
        let saved = preferences.rating(of: item) ?? 0
        VStack(alignment: .leading, spacing: 0) {
            Text("Your Rating")
                .font(Menu.headerFont)
                .foregroundStyle(.white.opacity(Menu.secondaryOpacity))
                .padding(.horizontal, Menu.headerInset)
                .frame(height: Menu.headerHeight, alignment: .leading)
            stars(saved: saved)
            Button {
                preferences.rate(item, stars: nil)
                onClose()
            } label: {
                Text("Clear Rating")
                    .font(Menu.titleFont)
                    .padding(.horizontal, Menu.rowInset)
                    .frame(height: Menu.rowHeight)
            }
            .buttonStyle(PlayerMenuView.ItemButtonStyle(showsFocus: true))
            .focused(focus, equals: .clear)
        }
        .padding(.vertical, Menu.verticalPadding)
        .frame(width: Menu.width)
        .clipShape(.rect(cornerRadius: Menu.cornerRadius))
        .glassEffect(.regular, in: .rect(cornerRadius: Menu.cornerRadius))
        .onExitCommand(perform: onClose)
    }

    /// The stars, filled to where focus is along them, else to the rating kept, with the stops over them.
    private func stars(saved: Double) -> some View {
        let focused = focusedHalves
        let shown = focused.map { Double($0) / 2 } ?? saved
        let isFocused = focused != nil
        return HStack(spacing: Metrics.starSpacing) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: Self.symbol(for: star, filledTo: shown))
            }
            Spacer(minLength: Metrics.valueSpacing)
            Text(Self.label(for: shown))
                .monospacedDigit()
                .fixedSize()
        }
        .font(Menu.titleFont)
        .foregroundStyle(isFocused ? .black : .white)
        .padding(.horizontal, Menu.rowInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Menu.rowHeight)
        .background {
            Capsule()
                .fill(.white.opacity(Menu.focusedOpacity))
                .padding(.horizontal, Menu.capsuleInset)
                .padding(.vertical, -Menu.capsuleOverhang)
                .opacity(isFocused ? 1 : 0)
        }
        .overlay { stops(saved: saved) }
        .animation(Menu.focusMotion, value: isFocused)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your Rating")
    }

    /// A stop for no stars and each half star, side by side across the row, too faint to see: focus
    /// can't rest on something clear.
    private func stops(saved: Double) -> some View {
        HStack(spacing: 0) {
            ForEach(0...Metrics.halves, id: \.self) { halves in
                let stars = Double(halves) / 2
                Button {
                    preferences.rate(item, stars: stars)
                    onClose()
                } label: {
                    Color.black.opacity(Menu.faintest)
                }
                .buttonStyle(MediaCardButtonStyle())
                .focused(focus, equals: .stars(halves: halves))
                .accessibilityLabel(Self.label(for: stars))
            }
        }
        .padding(.horizontal, Menu.capsuleInset)
        .focusSection()
        // Up from Clear Rating comes back to the rating kept.
        .defaultFocus(focus, .stars(halves: Self.halves(of: saved)), priority: .userInitiated)
    }

    /// The stop focus is on, if it's on one.
    private var focusedHalves: Int? {
        if case .stars(let halves) = focus.wrappedValue { halves } else { nil }
    }

    /// The stop for `stars` stars.
    static func halves(of stars: Double) -> Int {
        min(Metrics.halves, max(0, Int((stars * 2).rounded())))
    }

    /// A star filled, half filled or empty, for `stars` stars.
    private static func symbol(for star: Int, filledTo stars: Double) -> String {
        let star = Double(star)
        if stars >= star { return "star.fill" }
        if stars >= star - 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }

    /// "4.5", or "Not Rated" without stars.
    private static func label(for stars: Double) -> String {
        stars > 0 ? stars.formatted(.number.precision(.fractionLength(1))) : "Not Rated"
    }

    private typealias Menu = PlayerMenuView.Metrics

    struct Metrics {
        /// Five stars, in halves.
        static let halves = 10
        static let starSpacing: CGFloat = 6
        static let valueSpacing: CGFloat = 24
        /// Between the panel and the star it opens over.
        static let buttonSpacing: CGFloat = 24
    }
}
