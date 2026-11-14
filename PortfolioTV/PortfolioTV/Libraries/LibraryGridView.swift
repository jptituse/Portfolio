import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// The chosen sidebar item's items, as a grid of posters that keep their size: posters for movies and
/// shows, stills for videos, squares for albums. Only the posters on screen are made, and more items
/// load as it nears the end of what's loaded. A new sidebar item cross-fades in, starting at the top.
/// Selecting a poster hands it to `expansion`, which grows its card to full screen while the poster
/// hides underneath.
///
/// It runs to the top and bottom of the screen, with `margins` keeping its first and last rows clear of
/// the edges: a lazy grid drops rows that leave its frame, though a row partly above it still shows.
struct LibraryGridView: View {
    let viewModel: LibraryViewModel
    let expansion: MediaCardExpansionViewModel
    var focus: FocusState<LibraryFocus?>.Binding
    let margins: EdgeInsets

    var body: some View {
        // The sidebar item's grid, drawn afresh for each sidebar item, so the new one cross-fades over
        // the old.
        ZStack {
            grid
                .id(viewModel.shownSidebarItem)
                .transition(.opacity)
        }
        .animation(Metrics.sidebarItemCrossFade, value: viewModel.shownSidebarItem)
        .focusSection()
        // Once the expanded card gives up focus, it falls back onto the poster the card shrank onto.
        .defaultFocus(focus, expansion.item.map(LibraryFocus.poster), priority: .userInitiated)
        .ignoresSafeArea(edges: .vertical)
        .overlay(alignment: .topLeading) {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else if let message = viewModel.message {
                    Text(message)
                        .foregroundStyle(.secondary)
                }
            }
            // Where the first row starts.
            .padding(.top, margins.top)
        }
    }

    private var grid: some View {
        let size = Metrics.posterSize(for: viewModel.posterAspectRatio)
        return ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: size.width, maximum: size.width), spacing: Metrics.columnSpacing, alignment: .top)],
                alignment: .leading,
                spacing: Metrics.rowSpacing
            ) {
                ForEach(viewModel.items) { item in
                    Button {
                        expansion.select(viewModel.card(for: item))
                    } label: {
                        MediaCardView(viewModel: viewModel.card(for: item))
                            .frame(width: size.width, height: size.height)
                            .contentShape(.hoverEffect, .rect(cornerRadius: MediaCardView.Metrics.posterCornerRadius))
                            .hoverEffect(.highlight)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                                expansion.posterMoved(item.id, to: frame)
                            }
                    }
                    .buttonStyle(MediaCardButtonStyle())
                    // Hidden under its card while that's open.
                    .opacity(expansion.item == item.id ? 0 : 1)
                    .focused(focus, equals: .poster(item.id))
                    .accessibilityIdentifier("library.poster")
                    .accessibilityLabel(item.name)
                    .onAppear { viewModel.itemAppeared(item) }
                }
            }
        }
        .contentMargins(.top, margins.top, for: .scrollContent)
        .contentMargins(.bottom, margins.bottom + Metrics.bottomPadding, for: .scrollContent)
        .scrollClipDisabled()
    }
}

extension LibraryGridView {
    struct Metrics {
        static let columnSpacing: CGFloat = 40
        static let rowSpacing: CGFloat = 48
        static let bottomPadding: CGFloat = 20
        /// One sidebar item's grid giving way to another's.
        static var sidebarItemCrossFade: Animation { .easeInOut(duration: 0.25) }

        /// A grid poster's size for a shape, width over height: as tall as a row's poster when it's
        /// taller than wide, otherwise as wide as two.
        static func posterSize(for aspectRatio: Double) -> CGSize {
            let ratio = CGFloat(aspectRatio)
            if ratio < 1 {
                return CGSize(width: portraitHeight * ratio, height: portraitHeight)
            }
            return CGSize(width: landscapeWidth, height: landscapeWidth / ratio)
        }

        static let portraitHeight: CGFloat = 375
        static let landscapeWidth: CGFloat = 420
    }
}
