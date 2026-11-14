import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// A related media group at rest: a titled, horizontally scrolling row of posters inside the browsing
/// view. Opening the row hands its items over to `RelatedMediaGroupCarouselView`, and the posters hide
/// underneath. Each poster reports where it is, so the cards can grow out of it and land back on it.
struct RelatedMediaGroupPosterView: View {
    let viewModel: RelatedMediaGroupViewModel
    let isOpen: Bool
    var focus: FocusState<BrowsingFocus?>.Binding
    let onSelect: (MediaItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.titleSpacing) {
            Text(viewModel.group.title)
                .font(.callout)
                .fontWeight(.semibold)
            ScrollViewReader { scroller in
                ScrollView(.horizontal) {
                    // Not lazy: a lazy stack estimates where the posters it isn't drawing are from the ones
                    // it has measured. A wide poster throws that off, and the whole row jumps.
                    HStack(spacing: Metrics.posterSpacing) {
                        ForEach(viewModel.group.items) { item in
                            poster(for: item)
                                .id(item.id)
                        }
                    }
                    .padding(.trailing, viewModel.isMakingRoomToExtend ? viewModel.extensionRoom : 0)
                    .padding(.vertical, Metrics.verticalPadding)
                }
                .scrollClipDisabled()
                // Keeps the wide poster in view. While the row is open it's hidden, and it must already
                // be in place when the cards close back onto it, so that doesn't animate. It does wait
                // for the row to be laid out at its new width, or the last poster has nowhere to go.
                .onChange(of: viewModel.extendedItem) { _, item in
                    guard let item else { return }
                    if isOpen {
                        Task { @MainActor in scroller.scrollTo(item) }
                    } else {
                        withAnimation(Metrics.extend) { scroller.scrollTo(item) }
                    }
                }
            }
        }
        // Up and Down always reach the row, focusing its nearest poster, even where none is directly
        // above or below.
        .focusSection()
        // Posters stay posters, whichever layer the browsing view is in.
        .environment(\.viewState, .root)
    }

    private func poster(for item: MediaItem) -> some View {
        let card = viewModel.card(for: item)
        let size = viewModel.posterSize(of: card)
        return Button {
            onSelect(item)
        } label: {
            MediaCardView(viewModel: card)
                .frame(width: size.width, height: size.height)
                .contentShape(.hoverEffect, .rect(cornerRadius: MediaCardView.Metrics.posterCornerRadius))
                .hoverEffect(.highlight)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    viewModel.posterMoved(item.id, to: frame)
                }
        }
        .buttonStyle(MediaCardButtonStyle())
        .opacity(isOpen ? 0 : 1)
        .focused(focus, equals: .poster(item.id, group: viewModel.id))
        .accessibilityIdentifier("browse.poster")
        .accessibilityLabel(item.name)
    }
}
