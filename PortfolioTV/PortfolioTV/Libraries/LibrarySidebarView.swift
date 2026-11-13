import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// A library's sidebar items, as a list beside its grid: Recently Added, all its items, and under
/// "Genres", each of its genres. The grid follows the focused sidebar item once focus rests on it, and
/// selecting a sidebar item shows it at once. Only the sidebar item showing has a platter; the focused
/// one brightens and grows a little. Coming into the list lands on the sidebar item showing.
struct LibrarySidebarView: View {
    let viewModel: LibraryViewModel
    var focus: FocusState<LibraryFocus?>.Binding

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                Text(viewModel.title)
                    .font(.title2)
                    .bold()
                    .padding(.bottom, Metrics.titleSpacing)
                ForEach(viewModel.mainSidebarItems, id: \.self, content: row)
                if !viewModel.genres.isEmpty {
                    Text("Genres")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.top, Metrics.headingSpacing)
                    ForEach(viewModel.genres) { genre in
                        row(for: .genre(genre))
                    }
                }
            }
            .padding(.vertical, Metrics.verticalPadding)
        }
        .scrollClipDisabled()
        .focusSection()
        .defaultFocus(focus, .sidebarItem(viewModel.chosenSidebarItem), priority: .userInitiated)
    }

    private func row(for sidebarItem: LibrarySidebarItem) -> some View {
        Button {
            viewModel.sidebarItemSelected(sidebarItem)
        } label: {
            Text(viewModel.title(of: sidebarItem))
                .lineLimit(1)
        }
        .buttonStyle(SidebarItemButtonStyle(isShowing: sidebarItem == viewModel.chosenSidebarItem))
        .focused(focus, equals: .sidebarItem(sidebarItem))
        // Marked as selected rather than renamed, so the sidebar item keeps its name for VoiceOver and
        // tests.
        .accessibilityAddTraits(sidebarItem == viewModel.chosenSidebarItem ? .isSelected : [])
        .accessibilityIdentifier("library.sidebarItem")
    }
}

extension LibrarySidebarView {
    /// A sidebar item: its name, on a platter only while it's the sidebar item showing, brightening and
    /// growing a little while it's focused.
    struct SidebarItemButtonStyle: ButtonStyle {
        let isShowing: Bool

        func makeBody(configuration: Configuration) -> some View {
            SidebarItemLabel(label: configuration.label, isShowing: isShowing, isPressed: configuration.isPressed)
        }
    }

    private struct SidebarItemLabel<Label: View>: View {
        let label: Label
        let isShowing: Bool
        let isPressed: Bool

        @Environment(\.isFocused) private var isFocused

        var body: some View {
            label
                .font(.callout)
                .fontWeight(isFocused ? .semibold : .regular)
                .foregroundStyle(isFocused || isShowing ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.rowHorizontalPadding)
                .padding(.vertical, Metrics.rowVerticalPadding)
                .background {
                    RoundedRectangle(cornerRadius: Metrics.platterCornerRadius)
                        .fill(.white.opacity(isShowing ? Metrics.platterOpacity : 0))
                }
                .scaleEffect(isPressed ? 1 : isFocused ? Metrics.focusedScale : 1)
                .animation(.easeOut(duration: Metrics.focusAnimationDuration), value: isFocused)
        }
    }

    struct Metrics {
        static let rowSpacing: CGFloat = 4
        static let rowHorizontalPadding: CGFloat = 20
        static let rowVerticalPadding: CGFloat = 12
        static let platterCornerRadius: CGFloat = 16
        /// The gray of the system's resting platters: white at this opacity over the background.
        static let platterOpacity = 0.1
        static let focusedScale: CGFloat = 1.06
        static let focusAnimationDuration = 0.15
        static let titleSpacing: CGFloat = 16
        static let headingSpacing: CGFloat = 28
        static let verticalPadding: CGFloat = 20
    }
}
