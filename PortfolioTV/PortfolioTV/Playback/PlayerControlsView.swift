import PortfolioSharedPlaybackEngine
import PortfolioSharedUI
import SwiftUI

/// The player's transport bar, drawn as the system player draws it over its darkened bottom (which
/// `PlayerView` draws, under the subtitles): what's playing (its title, and what it belongs to above it)
/// with the menu buttons at the other end of its line (`PlayerMenusView`), a glass bar filled as far as playback has got, with a line at the playhead, the
/// elapsed time under the playhead (and a pause symbol beside it while paused), and the time left under
/// the bar's end.
///
/// Scrubbing, it's the system's scrubbing bar: the title gone, the bar taller about its middle (taller
/// still while a finger moves the spot, without the pause symbol), the spot marked by a line reaching up
/// above the bar and where playback is by a thinner one, each with a gap cut either side, and the stretch
/// between them gray, and the menus gone too. The system's shows a preview of the spot where the title
/// was, which needs the server's trickplay images.
///
/// Only the title, bar and times follow the time (`NowPlaying`), so as the media plays nothing else is
/// drawn again, the menus least of all.
struct PlayerControlsView: View {
    let viewModel: PlayerViewModel
    /// Whether a finger is moving the scrubbing spot, or it's coasting.
    let isInteracting: Bool
    var focus: FocusState<PlayerView.Focus?>.Binding
    /// How subtitles would look with the caption style that has focus in a menu, if one has.
    @Binding var previewStyle: CaptionStyle?
    /// Down from the menus.
    let onLeaveMenus: () -> Void
    /// How far up from the bottom the title, bar and times reach, as it changes.
    let onHeightChange: (CGFloat) -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { proxy in
                let scrubbing = viewModel.isScrubbing
                let interacting = scrubbing && isInteracting
                let height = scrubbing ? (interacting ? Metrics.interactingBarHeight : Metrics.scrubbingBarHeight) : Metrics.barHeight
                NowPlaying(viewModel: viewModel, width: proxy.size.width, barHeight: height, isScrubbing: scrubbing, isInteracting: interacting)
                    .onGeometryChange(for: CGFloat.self, of: { $0.bounds(of: .named(Self.space))?.maxY ?? 0 }, action: onHeightChange)
                    .allowsHitTesting(false)
                    // Centered on the title's line, at the bar's end.
                    .overlay(alignment: Alignment(horizontal: .trailing, vertical: .titleLine)) {
                        PlayerMenusView(viewModel: viewModel, focus: focus, previewStyle: $previewStyle)
                            // Down in an open menu moves within it.
                            .onMoveCommand { if $0 == .down, viewModel.openMenuRoot == nil { onLeaveMenus() } }
                            .alignmentGuide(.titleLine) { $0[VerticalAlignment.center] }
                            .opacity(scrubbing ? 0 : 1)
                            .disabled(!viewModel.showsControls || scrubbing)
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    // Growing about its middle: the times go down with its bottom.
                    .offset(y: (height - Metrics.barHeight) / 2)
                    .animation(interacting ? Metrics.growing : Metrics.settling, value: height)
            }
            .padding(.horizontal, Metrics.sideInset)
            .padding(.bottom, Metrics.bottomInset)
        }
        .coordinateSpace(.named(Self.space))
    }

    nonisolated private static let space = "PlayerControlsView"
}

extension PlayerControlsView {
    /// What's playing and how far along it is: the title, the bar and the times. It alone reads the
    /// time, so it alone is drawn again as the media plays.
    struct NowPlaying: View {
        let viewModel: PlayerViewModel
        let width: CGFloat
        let barHeight: CGFloat
        let isScrubbing: Bool
        /// Whether a finger is moving the scrubbing spot, or it's coasting.
        let isInteracting: Bool

        /// The widths of the elapsed time, the pause symbol beside it and the time left, to keep the
        /// elapsed time within the bar and clear of the time left.
        @State private var elapsedWidth: CGFloat = 0
        @State private var pauseWidth: CGFloat = 0
        @State private var remainingWidth: CGFloat = 0

        var body: some View {
            let playhead = width * viewModel.progress
            // The playhead and the time go straight to each new position, as the system's do. Gliding
            // there, the time cross-faded from one to the next, and its digits blurred.
            VStack(alignment: .leading, spacing: 0) {
                titles
                    .padding(.bottom, Metrics.titleSpacing)
                    .opacity(isScrubbing ? 0 : 1)
                bar(height: barHeight, playhead: playhead, playback: width * viewModel.playbackProgress, scrubbing: isScrubbing)
                    .padding(.bottom, Metrics.labelSpacing)
                labels(width: width, playhead: playhead, showsPause: viewModel.isPaused && !isInteracting)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("player.controls")
            .accessibilityLabel(viewModel.title)
            .accessibilityValue("\(viewModel.elapsedLabel), \(viewModel.remainingLabel)")
        }

        private var titles: some View {
            VStack(alignment: .leading, spacing: Metrics.subtitleSpacing) {
                if let subtitle = viewModel.subtitle {
                    Text(subtitle)
                        .font(.caption)
                }
                Text(viewModel.title)
                    .font(.title2)
                    .bold()
                    .alignmentGuide(.titleLine) { $0[VerticalAlignment.center] }
            }
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, Metrics.titleInset)
        }

        /// A glass capsule `height` tall, filled up to the playhead, with a line there. Scrubbing, `playhead`
        /// is the spot and `playback` where playback is, with the part before both filled and the part
        /// between them gray.
        private func bar(height: CGFloat, playhead: CGFloat, playback: CGFloat, scrubbing: Bool) -> some View {
            let start = min(playhead, playback)
            let shape = BarShape(lines: scrubbing ? [
                BarShape.Line(center: playhead, width: Metrics.playheadWidth),
                BarShape.Line(center: playback, width: Metrics.playbackLineWidth),
            ] : [], gap: Metrics.lineGap)
            return Color.clear
                .glassEffect(.regular, in: shape)
                .overlay(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        fill(from: 0, to: start, opacity: scrubbing ? Metrics.scrubbingPlayedOpacity : Metrics.playedOpacity)
                        fill(from: start, to: max(playhead, playback), opacity: Metrics.betweenOpacity)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipShape(shape)
                }
                // Where playback is while scrubbing, inside the bar.
                .overlay(alignment: .leading) {
                    line(at: playback, width: Metrics.playbackLineWidth)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipShape(Capsule())
                        .opacity(scrubbing ? 1 : 0)
                }
                // The playhead at rest, a little taller than the bar; scrubbing, the spot's line reaching up
                // above the bar and a point below it, whatever the bar's rounded ends.
                .overlay(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        line(at: playhead, width: Metrics.playheadWidth)
                            .frame(height: height + Metrics.playheadOverhang * 2)
                            .offset(y: -Metrics.playheadOverhang)
                            .opacity(scrubbing ? 0 : 1)
                        line(at: playhead, width: Metrics.playheadWidth)
                            .frame(height: Metrics.scrubbingReach + height + Metrics.scrubbingOverhang)
                            .offset(y: -Metrics.scrubbingReach)
                            .opacity(scrubbing ? 1 : 0)
                    }
                }
                .frame(height: height)
        }

        /// The bar filled from `start` to `end`, at `opacity`.
        private func fill(from start: CGFloat, to end: CGFloat, opacity: Double) -> some View {
            Rectangle()
                .fill(.white.opacity(opacity))
                .frame(width: max(0, end - start))
                .offset(x: start)
        }

        /// A white line `width` wide, centered on `x`.
        private func line(at x: CGFloat, width: CGFloat) -> some View {
            Rectangle()
                .fill(.white)
                .frame(width: width)
                .offset(x: x - width / 2)
        }

        /// The elapsed time centered under the playhead, as far as the bar reaches, and the time left at
        /// the bar's end, which gives way when the elapsed time comes up to it.
        /// The pause symbol is an overlay, so the row keeps its height, and the bar its place, as it comes
        /// and goes.
        private func labels(width: CGFloat, playhead: CGFloat, showsPause: Bool) -> some View {
            let pause = showsPause ? Metrics.pauseSpacing + pauseWidth : 0
            let inset = Metrics.labelInset
            let elapsedOffset = min(max(inset, playhead - elapsedWidth / 2), max(inset, width - inset - elapsedWidth - pause))
            let remainingIsClear = elapsedOffset + elapsedWidth + pause + Metrics.labelGap <= width - inset - remainingWidth
            return ZStack(alignment: .topLeading) {
                Text(viewModel.elapsedLabel)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { elapsedWidth = $0 }
                    .overlay(alignment: .leading) {
                        Image(systemName: "pause.circle")
                            .imageScale(.large)
                            .fixedSize()
                            .onGeometryChange(for: CGFloat.self, of: \.size.width) { pauseWidth = $0 }
                            .offset(x: elapsedWidth + Metrics.pauseSpacing)
                            .opacity(showsPause ? 1 : 0)
                    }
                    .offset(x: elapsedOffset)
                Text(viewModel.remainingLabel)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { remainingWidth = $0 }
                    .opacity(remainingIsClear ? 1 : 0)
                    .padding(.trailing, inset)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(Metrics.labelFont)
            .monospacedDigit()
            .foregroundStyle(.white)
            // The times change at once, even as scrubbing starts or stops in an animation: a time that
            // cross-faded blurred.
            .contentTransition(.identity)
        }
    }
}

extension VerticalAlignment {
    /// The middle of the title's line, which the menus are centered on.
    private enum TitleLine: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[VerticalAlignment.center]
        }
    }

    static let titleLine = VerticalAlignment(TitleLine.self)
}

extension PlayerControlsView {
    /// The bar's capsule, with a gap `gap` wide cut either side of each line, through the glass and the
    /// fill.
    nonisolated struct BarShape: Shape {
        struct Line {
            let center: CGFloat
            let width: CGFloat
        }

        let lines: [Line]
        let gap: CGFloat

        func path(in rect: CGRect) -> Path {
            let capsule = Capsule().path(in: rect)
            guard !lines.isEmpty else { return capsule }
            var gaps = Path()
            for line in lines {
                gaps.addRect(CGRect(x: line.center - line.width / 2 - gap, y: rect.minY, width: gap, height: rect.height))
                gaps.addRect(CGRect(x: line.center + line.width / 2, y: rect.minY, width: gap, height: rect.height))
            }
            return capsule.subtracting(gaps)
        }
    }
}

extension PlayerControlsView {
    /// Measured from the system player on a 4K screen.
    struct Metrics {
        static let sideInset: CGFloat = 80
        /// From the screen's bottom to the bottom of the time labels.
        static let bottomInset: CGFloat = 127
        static let barHeight: CGFloat = 14
        static let labelSpacing: CGFloat = 8.5
        static let titleSpacing: CGFloat = 32
        static let subtitleSpacing: CGFloat = 14.5
        /// How far the title and the time labels sit inside the bar's ends.
        static let titleInset: CGFloat = 4
        static let labelInset: CGFloat = 3
        static let playheadWidth: CGFloat = 2
        static let playheadOverhang: CGFloat = 0.5
        static let playedOpacity = 0.45
        static let pauseSpacing: CGFloat = 14
        /// The least room between the elapsed time and the time left, for both to show.
        static let labelGap: CGFloat = 24
        static var labelFont: Font { .caption2.bold() }

        // Scrubbing: the heights and springs are AVKit's (`AVTheme`, `AVNowPlayingTransportBar`); the
        // rest is measured from recordings of the TV app scrubbing on an Apple TV, at 1080p, so to about
        // a point.
        static let scrubbingBarHeight: CGFloat = 18
        /// While a finger moves the spot, or it's coasting.
        static let interactingBarHeight: CGFloat = 20
        /// How far the spot's line reaches above the bar, to where the preview's bottom would be, and
        /// below it.
        static let scrubbingReach: CGFloat = 21.5
        static let scrubbingOverhang: CGFloat = 1
        static let playbackLineWidth: CGFloat = 1.5
        /// The gap cut either side of each line.
        static let lineGap: CGFloat = 1
        static let scrubbingPlayedOpacity = 0.4
        /// The part between the spot and where playback is.
        static let betweenOpacity = 0.19
        /// Growing as a finger takes the spot, and settling back.
        static var growing: Animation { .spring(duration: 0.3, bounce: 0.4) }
        static var settling: Animation { .spring(duration: 0.4, bounce: -0.1) }
    }
}
