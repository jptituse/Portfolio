import PortfolioShared
import PortfolioSharedPlaybackEngine
import PortfolioSharedUI
import SwiftUI

/// The player's transport bar, drawn as the system player draws it over its darkened bottom (which
/// `PlayerView` draws, under the subtitles): what's playing (its title, and what it belongs to above it)
/// with the menu buttons at the other end of its line (`PlayerMenusView`), a glass bar filled as far as
/// playback has got, with a line at the playhead, the elapsed time under the playhead, and the time left
/// under the bar's end. Beside the elapsed time is a symbol (`PlayerViewModel.timeBadge(isInteracting:)`):
/// which way the needle's moving by itself, and at which speed; a skip just made; or a pause symbol while
/// paused. Going back, it's before the time; on, and paused, after it.
///
/// Scrubbing, it's the system's scrubbing bar: the title gone, the bar taller about its middle while a
/// finger moves the spot (without the pause symbol), the spot marked by a line reaching up
/// above the bar and where playback is by a thinner one, each with a gap cut either side, and the stretch
/// between them gray, and the menus gone too. Above the bar, where the title was, is the server's
/// picture of the spot (`PlayerViewModel.scrubPreview`), where it has trickplay pictures, as the
/// system's: centered on the spot, within the bar's ends, the spot's line reaching up to it. The needle
/// pushed on at an end stretches the bar a little past it, and the bar springs back once it lets go.
///
/// Only the title, bar and times follow the time (`NowPlaying`), so as the media plays nothing else is
/// drawn again, the menus least of all.
struct PlayerControlsView: View {
    let viewModel: PlayerViewModel
    /// Whether a finger is moving the scrubbing spot, or it's coasting.
    let isInteracting: Bool
    /// The end the bar stretches past, the needle pushed on there.
    let rubberBand: HorizontalEdge?
    /// Whether focus is on the bar, rather than the menus: away, the bar steps back, as the system's.
    let isBarFocused: Bool
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
                // AVKit's in-between height while paused on a spot (18) is left out: the bar stays as it
                // is until a finger moves the spot.
                let height = interacting ? Metrics.interactingBarHeight : Metrics.barHeight
                NowPlaying(
                    viewModel: viewModel,
                    width: proxy.size.width,
                    barHeight: height,
                    isScrubbing: scrubbing,
                    isInteracting: interacting,
                    rubberBand: scrubbing ? rubberBand : nil,
                    isFocused: isBarFocused
                )
                    .onGeometryChange(for: CGFloat.self, of: { $0.bounds(of: .named(Self.space))?.maxY ?? 0 }, action: onHeightChange)
                    .allowsHitTesting(false)
                    // Centered on the title's line, at the bar's end.
                    .overlay(alignment: Alignment(horizontal: .trailing, vertical: .titleLine)) {
                        PlayerMenusView(viewModel: viewModel, focus: focus, previewStyle: $previewStyle)
                            // Down in an open menu moves within it.
                            .onMoveCommand { if $0 == .down, viewModel.openMenuRoot == nil { onLeaveMenus() } }
                            .alignmentGuide(.titleLine) { $0[VerticalAlignment.center] }
                            .opacity(scrubbing ? 0 : 1)
                            // Back as the preview goes, when scrubbing ends; gone at once as it starts.
                            .animation(scrubbing ? nil : Metrics.scrubbingEnds, value: scrubbing)
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
        /// The end the bar stretches past, `Metrics.rubberBandStretch` further, the needle with it.
        let rubberBand: HorizontalEdge?
        /// Whether focus is on the bar. Away, as AVKit's unfocused bar (`_setBarFocusAppearance:`), the
        /// played part all but goes, and the playhead and the times are half as bright.
        let isFocused: Bool

        /// The widths of the elapsed time, the symbol beside it and the time left, to keep the elapsed
        /// time within the bar and clear of the time left.
        @State private var elapsedWidth: CGFloat = 0
        @State private var badgeWidth: CGFloat = 0
        @State private var remainingWidth: CGFloat = 0

        var body: some View {
            let barStart = rubberBand == .leading ? -Metrics.rubberBandStretch : 0
            let barWidth = width + (rubberBand == nil ? 0 : Metrics.rubberBandStretch)
            let playhead = barStart + barWidth * viewModel.progress
            // The playhead and the time go straight to each new position, as the system's do. Gliding
            // there, the time cross-faded from one to the next, and its digits blurred.
            VStack(alignment: .leading, spacing: 0) {
                titles
                    .padding(.bottom, Metrics.titleSpacing)
                    .opacity(isScrubbing ? 0 : 1)
                    .animation(isScrubbing ? nil : Metrics.scrubbingEnds, value: isScrubbing)
                bar(height: barHeight, playhead: playhead - barStart, playback: barWidth * viewModel.playbackProgress, scrubbing: isScrubbing)
                    .frame(width: barWidth)
                    .offset(x: barStart)
                    .frame(width: width, alignment: .leading)
                    .animation(Metrics.rubberBanding, value: rubberBand)
                    .animation(Metrics.focusChange, value: isFocused)
                    .overlay(alignment: .topLeading) {
                        preview(width: width, playhead: playhead)
                    }
                    .padding(.bottom, Metrics.labelSpacing)
                labels(width: width, playhead: playhead, badge: viewModel.timeBadge(isInteracting: isInteracting))
                    .opacity(isFocused ? 1 : Metrics.unfocusedOpacity)
                    .animation(Metrics.focusChange, value: isFocused)
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
            let played = scrubbing ? Metrics.scrubbingPlayedOpacity : isFocused ? Metrics.playedOpacity : Metrics.unfocusedPlayedOpacity
            let shape = BarShape(lines: scrubbing ? [
                BarShape.Line(center: playhead, width: Metrics.playheadWidth),
                BarShape.Line(center: playback, width: Metrics.playbackLineWidth),
            ] : [], gap: Metrics.lineGap)
            return Color.clear
                .glassEffect(.regular, in: shape)
                .overlay(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        fill(from: 0, to: start, opacity: played)
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
                            .opacity(scrubbing ? 0 : isFocused ? 1 : Metrics.unfocusedOpacity)
                        line(at: playhead, width: Metrics.playheadWidth)
                            .frame(height: Metrics.scrubbingReach + height + Metrics.scrubbingOverhang)
                            .offset(y: -Metrics.scrubbingReach)
                            .opacity(scrubbing ? 1 : 0)
                    }
                }
                .frame(height: height)
        }

        /// The server's picture of the spot, while scrubbing, above the bar: centered on the spot, but no
        /// further out than the bar's ends, its bottom where the spot's line reaches up to. It grows out
        /// of the spot's line, fading in, and shrinks back into it, on `Metrics.previewGrowing`.
        private func preview(width: CGFloat, playhead: CGFloat) -> some View {
            let picture = isScrubbing ? viewModel.scrubPreview : nil
            let previewWidth = Metrics.previewWidth
            // In the pictures' shape, which stays as one goes away.
            let previewHeight = previewWidth / (viewModel.trickplay?.aspectRatio ?? 16.0 / 9)
            let leading = min(max(0, playhead - previewWidth / 2), max(0, width - previewWidth))
            // Placed by layout rather than an offset, so it grows from where it is.
            return ZStack(alignment: .bottomLeading) {
                Color.clear
                if let picture {
                    Image(decorative: picture, scale: 1)
                        .resizable()
                        .frame(width: previewWidth, height: previewHeight)
                        .clipShape(RoundedRectangle(cornerRadius: Metrics.previewCornerRadius))
                        .padding(.leading, leading)
                        .transition(
                            .scale(scale: 0, anchor: UnitPoint(x: playhead / (leading + previewWidth), y: 1))
                                .combined(with: .opacity)
                        )
                }
            }
            .frame(width: width, height: previewHeight)
            .offset(y: -Metrics.scrubbingReach - previewHeight)
            .animation(picture != nil ? Metrics.previewGrowing : Metrics.scrubbingEnds, value: picture != nil)
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
        /// The symbol beside the elapsed time is an overlay, so the row keeps its height, and the bar its
        /// place, as it comes and goes.
        private func labels(width: CGFloat, playhead: CGFloat, badge: PlayerViewModel.TimeBadge?) -> some View {
            let badgeSpace = badge == nil ? 0 : Metrics.badgeSpacing + badgeWidth
            let before = badge?.side == .leading ? badgeSpace : 0
            let after = badge?.side == .trailing ? badgeSpace : 0
            let inset = Metrics.labelInset
            let elapsedOffset = min(max(inset + before, playhead - elapsedWidth / 2), max(inset + before, width - inset - elapsedWidth - after))
            let remainingIsClear = elapsedOffset + elapsedWidth + after + Metrics.labelGap <= width - inset - remainingWidth
            return ZStack(alignment: .topLeading) {
                Text(viewModel.elapsedLabel)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { elapsedWidth = $0 }
                    .overlay(alignment: .leading) {
                        if let badge {
                            HStack(spacing: Metrics.badgeNumberSpacing) {
                                Image(systemName: badge.symbol)
                                    .imageScale(.large)
                                    // A skip's arrow reaches above its circle: the circle goes where
                                    // the pause symbol's is.
                                    .offset(y: badge.kind == .skip ? -Metrics.skipArrowLift : 0)
                                if let number = badge.number {
                                    Text(number)
                                }
                            }
                            .fixedSize()
                            .onGeometryChange(for: CGFloat.self, of: \.size.width) { badgeWidth = $0 }
                            .offset(x: badge.side == .leading ? -(badgeWidth + Metrics.badgeSpacing) : elapsedWidth + Metrics.badgeSpacing)
                        }
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
            // cross-faded blurred. So do where they are and the symbol beside them: moving on the bar's
            // spring as a click began scrubbing, the pause symbol stayed beside a skip back's arrow, and
            // the arrow lay over the time while the time made room for it. Only Menu ending scrubbing
            // moves them, the time going back with the needle.
            .contentTransition(.identity)
            .transaction { if !$0.endsScrubbing { $0.animation = nil } }
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
        /// With focus away from the bar: the played part, as AVKit's measures over the picture (from
        /// half white to 4%), and the playhead and the times, at half; changed over five frames at
        /// 60 fps.
        static let unfocusedPlayedOpacity = 0.04
        static let unfocusedOpacity = 0.5
        static var focusChange: Animation { .easeOut(duration: 0.1) }
        /// From the elapsed time to the symbol beside it, and from the symbol to a drive's speed.
        static let badgeSpacing: CGFloat = 14
        static let badgeNumberSpacing: CGFloat = 12
        /// How far a skip's arrow is raised so its circle is level with the pause symbol's: centered as
        /// symbols are, its circle sat 1.75 points lower, measured at 4K.
        static let skipArrowLift: CGFloat = 1.75
        /// The least room between the elapsed time and the time left, for both to show.
        static let labelGap: CGFloat = 24
        static var labelFont: Font { .caption2.bold() }

        // Scrubbing: the height and springs are AVKit's (`AVTheme`, `AVNowPlayingTransportBar`); the
        // rest is measured from recordings of the TV app scrubbing on an Apple TV, at 1080p, so to about
        // a point.
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
        /// The server's picture of the spot: 400 points wide, in its own shape, as the TV app draws it,
        /// with its corners measured from AVKit's player at 4K.
        static let previewWidth: CGFloat = 400
        static let previewCornerRadius: CGFloat = 15
        /// How it grows out of the spot's line: fitted to AVKit's at 60 fps, from nothing to a little past
        /// its size (2.5%) and back, settled in about 0.35 s.
        static var previewGrowing: Animation { .spring(response: 0.27, dampingFraction: 0.78) }
        /// How Menu ends scrubbing (`Transaction.endsScrubbing`): the preview shrinks back into the
        /// spot's line as the needle, the time and the gray stretch collapse into where playback paused,
        /// and the title and menus come back. Ours, as the system's has nothing like it: Menu there drops
        /// the preview at once and hides the controls. On the growing spring, it was gone in 0.2 s.
        static var scrubbingEnds: Animation { .easeInOut(duration: 0.3) }
        /// How far the bar stretches past an end the needle's pushed on at, and on what spring: AVKit's
        /// (`_updateRubberBanding`, `_rubberBandingTimingParameters`).
        static let rubberBandStretch: CGFloat = 5
        static var rubberBanding: Animation { .spring(duration: 0.3, bounce: -0.1) }
        /// The part between the spot and where playback is.
        static let betweenOpacity = 0.19
        /// Growing as a finger takes the spot, and settling back.
        static var growing: Animation { .spring(duration: 0.3, bounce: 0.4) }
        static var settling: Animation { .spring(duration: 0.4, bounce: -0.1) }
    }
}

extension Transaction {
    /// Whether the change ends scrubbing without playing from the spot, as Menu does: the needle and the
    /// time go back to where playback paused, on `PlayerControlsView.Metrics.scrubbingEnds`, as the
    /// preview goes.
    var endsScrubbing: Bool {
        get { self[EndsScrubbingKey.self] }
        set { self[EndsScrubbingKey.self] = newValue }
    }

    private struct EndsScrubbingKey: TransactionKey {
        static let defaultValue = false
    }
}
