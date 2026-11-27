import PortfolioShared
import PortfolioSharedUI
import SwiftUI

/// An episode in its show's row of episodes, as the TV app's, in two parts. Its still, with how long it
/// is (or, where the user left off, how far along they are and the time left), plays it; with focus it
/// grows. Below, its number, name, what happens in it, its file's format and audio languages, when it
/// aired and its rating open its own page; with focus they sit on a platter, showing more of what
/// happens.
struct MediaDetailEpisodeView: View {
    let card: MediaCardViewModel
    var focus: FocusState<MediaDetailFocus?>.Binding
    let onPlay: () -> Void
    let onOpen: () -> Void

    @Environment(\.hidesSpoilers) private var hidesSpoilers

    var body: some View {
        let isSpoiler = card.isSpoiler(hidingSpoilers: hidesSpoilers)
        let stillHasFocus = focus.wrappedValue == .episode(card.item.id)
        let textHasFocus = focus.wrappedValue == .episodeInfo(card.item.id)
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onPlay) {
                still(blurred: isSpoiler)
                    .frame(width: Metrics.stillSize.width, height: Metrics.stillSize.height)
                    .overlay(alignment: .bottomLeading) { playInfo }
                    .clipShape(.rect(cornerRadius: Metrics.cornerRadius))
                    .scaleEffect(stillHasFocus ? Metrics.focusedScale : 1)
                    .shadow(color: .black.opacity(stillHasFocus ? Metrics.shadowOpacity : 0), radius: Metrics.shadowRadius, y: Metrics.shadowOffset)
            }
            .buttonStyle(MediaCardButtonStyle())
            .focused(focus, equals: .episode(card.item.id))
            .zIndex(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Play \(name)")
            .accessibilityValue(card.timeLeftLabel ?? "")

            Button(action: onOpen) {
                text(hidingOverview: isSpoiler, hasFocus: textHasFocus)
                    .padding(Metrics.textInset)
                    .frame(
                        width: Metrics.stillSize.width + Metrics.textInset * 2,
                        height: textHasFocus ? Metrics.focusedTextHeight : Metrics.textHeight,
                        alignment: .topLeading
                    )
                    .background(.white.opacity(textHasFocus ? Metrics.platterOpacity : 0), in: .rect(cornerRadius: Metrics.platterCornerRadius))
            }
            .buttonStyle(MediaCardButtonStyle())
            .focused(focus, equals: .episodeInfo(card.item.id))
            .padding(.horizontal, -Metrics.textInset)
            // Clear of the still as it grows.
            .padding(.top, Metrics.textSpacing - Metrics.textInset + (stillHasFocus ? Metrics.stillGrowth : 0))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityValue(isSpoiler ? "" : card.item.overview ?? "")
        }
        // As tall with focus as without, so the page doesn't move as focus comes and goes.
        .frame(width: Metrics.stillSize.width, height: Metrics.height, alignment: .top)
        .animation(Metrics.focusMotion, value: stillHasFocus)
        .animation(Metrics.focusMotion, value: textHasFocus)
    }

    /// "Episode 5, The Bridge".
    private var name: String {
        [Self.number(of: card.item), card.item.name].compactMap { $0 }.joined(separator: ", ")
    }

    /// The episode's still, else its show's landscape art.
    private func still(blurred: Bool) -> some View {
        RemoteImageView(url: card.posterArtworkURL ?? card.landscapeArtworkURL) { image in
            image
                .resizable()
                .scaledToFill()
                .blur(radius: blurred ? MediaCardView.Metrics.spoilerBlur : 0, opaque: true)
        } placeholder: {
            ImagePlaceholderView()
        }
    }

    /// "▶ 29m", or "▶ ━━ 12m" partway through, over the still's corner.
    private var playInfo: some View {
        HStack(spacing: Metrics.playInfoSpacing) {
            Image(systemName: "play.fill")
            if let progress = card.progress {
                Capsule()
                    .fill(.white.opacity(Metrics.barTrackOpacity))
                    .frame(width: Metrics.barWidth, height: Metrics.barHeight)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.white)
                            .frame(width: Metrics.barWidth * progress)
                    }
            }
            if let remaining = card.timeRemainingLabel {
                Text(remaining)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(Metrics.playInfoShadowOpacity), radius: Metrics.playInfoShadowRadius)
        .padding(Metrics.playInfoInset)
    }

    /// "EPISODE 1", its name, what happens, its file's format and audio languages, then when it aired
    /// and its rating.
    private func text(hidingOverview: Bool, hasFocus: Bool) -> some View {
        VStack(alignment: .leading, spacing: Metrics.lineSpacing) {
            if let number = Self.number(of: card.item) {
                Text(number.uppercased())
                    .font(Metrics.numberFont)
                    .foregroundStyle(.white.opacity(Metrics.dimmestOpacity))
            }
            Text(card.item.name)
                .font(Metrics.nameFont)
                .lineLimit(1)
            if !hidingOverview, let overview = card.item.overview {
                overviewText(overview, lineLimit: hasFocus ? Metrics.focusedOverviewLineLimit : Metrics.overviewLineLimit)
            }
            Spacer(minLength: 0)
            tags
            HStack(spacing: Metrics.lineSpacing * 2) {
                if let aired = card.item.premiereDate {
                    // A day, which the server gives as midnight in UTC.
                    Text(aired.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: .gmt)))
                } else if let year = card.item.productionYear {
                    Text(String(year))
                }
                if let rating = card.item.officialRating {
                    Self.tag(rating)
                }
            }
            .font(Metrics.textFont)
            .foregroundStyle(.white.opacity(Metrics.dimOpacity))
        }
    }

    /// What happens in it, in as many of `lineLimit` lines as fit. Its lines break as they do with the
    /// most it ever shows, so gaining or losing lines as focus comes and goes moves no word: the last
    /// line showing ends on a whole word and an ellipsis (`OverviewRenderer`). Left to Text, the last
    /// line took as much of the next one's first word as fit, which moved back down as the lines came.
    private func overviewText(_ overview: String, lineLimit: Int) -> some View {
        // Takes the space Text itself would, at as many lines as fit, for the lines drawn over it.
        Text(overview)
            .lineLimit(lineLimit)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hidden()
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    Text(overview)
                        .lineLimit(Metrics.focusedOverviewLineLimit + 1)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: proxy.size.width, alignment: .leading)
                        .textRenderer(OverviewRenderer(
                            characters: Array(overview.utf16),
                            height: proxy.size.height,
                            finalHeight: proxy.size.height,
                            width: proxy.size.width,
                            ellipsis: Text(verbatim: "…").font(Metrics.textFont).foregroundStyle(.white.opacity(Metrics.dimOpacity))
                        ))
                }
            }
            .font(Metrics.textFont)
            .foregroundStyle(.white.opacity(Metrics.dimOpacity))
    }

    /// Its file's format ("4K", "Dolby Vision") and its audio's languages ("EN", "JA"), boxed and small,
    /// as many as fit: the languages go first when they don't, then the format's last.
    @ViewBuilder private var tags: some View {
        let format = card.formatBadges
        let languages = card.audioLanguageTags
        if !format.isEmpty || !languages.isEmpty {
            ViewThatFits(in: .horizontal) {
                ForEach(Array(Self.tagLines(format: format, languages: languages).enumerated()), id: \.offset) { _, line in
                    HStack(spacing: Metrics.tagSpacing) {
                        ForEach(line, id: \.self, content: Self.tag)
                    }
                    .fixedSize()
                }
            }
            .foregroundStyle(.white.opacity(Metrics.tagOpacity))
            .accessibilityHidden(true)
        }
    }

    /// Every tag, then fewer and fewer, for `ViewThatFits` to take the first that fits.
    private static func tagLines(format: [String], languages: [String]) -> [[String]] {
        var lines = [format + languages]
        for count in stride(from: languages.count - 1, through: 0, by: -1) {
            lines.append(format + languages.prefix(count))
        }
        for count in stride(from: format.count - 1, through: 1, by: -1) {
            lines.append(Array(format.prefix(count)))
        }
        return lines
    }

    /// A tag in a box: a format, a language or a rating.
    private static func tag(_ label: String) -> some View {
        Text(label)
            .font(Metrics.tagFont)
            .padding(.horizontal, Metrics.ratingPadding)
            .overlay(RoundedRectangle(cornerRadius: Metrics.ratingCornerRadius).stroke(lineWidth: Metrics.ratingLineWidth))
    }

    /// "Episode 5", or "Special" for one in the specials.
    static func number(of item: MediaItem) -> String? {
        if item.episode?.seasonNumber == 0 { return "Special" }
        return item.episode?.episodeNumber.map { "Episode \($0)" }
    }
}

extension MediaDetailEpisodeView {
    /// Draws an episode's synopsis broken into lines as it is with the most it ever shows, only the lines
    /// within `height`, the last of them ending on a whole word and an ellipsis where more follows. As
    /// the space grows or shrinks with focus, the lines it passes fade in or out where they are.
    ///
    /// Nonisolated, as is all it reads: on an Apple TV, SwiftUI draws it on its own render thread while
    /// it animates, and isolated to the main actor (the target's default) it trapped there. The
    /// simulator draws it on the main thread.
    nonisolated struct OverviewRenderer: TextRenderer {
        /// The synopsis's UTF-16 code units, which its glyphs' character indices count from its first,
        /// to tell where its words end.
        let characters: [UInt16]
        /// How tall the space for it is: it grows and shrinks with focus.
        var height: CGFloat
        /// How tall the space ends up, which decides which line ends on the ellipsis: from the start of
        /// the change, so no word comes or goes partway.
        let finalHeight: CGFloat
        /// How wide its lines can be.
        let width: CGFloat
        let ellipsis: Text

        var animatableData: CGFloat {
            get { height }
            set { height = newValue }
        }

        func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
            let fitting = layout.prefix { $0.typographicBounds.rect.maxY <= finalHeight + Metrics.lineTolerance }.count
            // The first character's index, which the others count from.
            let start = layout.first?.flatMap(\.characterIndices).min()
            for (index, line) in layout.enumerated() {
                let bounds = line.typographicBounds.rect
                let shown = Self.snapped((height - bounds.minY) / max(bounds.height, 1))
                guard shown > 0 else { break }
                var lineContext = ctx
                lineContext.opacity = shown
                if index == fitting - 1, fitting < layout.count {
                    drawEndingOnEllipsis(line, from: start, in: &lineContext)
                } else {
                    lineContext.draw(line)
                }
            }
        }

        /// How much of a line shows, from how much of it is within the space: all of it or none when
        /// it's all but so.
        private static func snapped(_ fraction: CGFloat) -> CGFloat {
            fraction > 1 - Metrics.fadeSnap ? 1 : fraction < Metrics.fadeSnap ? 0 : fraction
        }

        /// Draws `line` up to the last whole word that leaves room for the ellipsis, then the ellipsis.
        private func drawEndingOnEllipsis(_ line: Text.Layout.Line, from start: Text.Layout.CharacterIndex?, in ctx: inout GraphicsContext) {
            // Each glyph, in order, as its run and its place in it, and whether it's a space.
            let glyphs = line.indices.flatMap { run in
                line[run].indices.map { glyph in (run: run, glyph: glyph, isSpace: isSpace(line[run], glyph, from: start)) }
            }
            guard start != nil, line.first?.layoutDirection != .rightToLeft,
                  var last = glyphs.lastIndex(where: { !$0.isSpace }) else {
                ctx.draw(line)
                return
            }
            let ellipsis = ctx.resolve(self.ellipsis)
            let size = ellipsis.measure(in: CGSize(width: CGFloat.infinity, height: .infinity))
            func end(_ index: Int) -> CGFloat {
                line[glyphs[index].run][glyphs[index].glyph].typographicBounds.rect.maxX
            }
            // Back a word at a time until the ellipsis fits after it; within a word filling the line,
            // a glyph at a time.
            while end(last) + size.width > width {
                if let space = glyphs[..<last].lastIndex(where: { $0.isSpace }),
                   let previous = glyphs[..<space].lastIndex(where: { !$0.isSpace }) {
                    last = previous
                } else if last > 0 {
                    last -= 1
                } else {
                    break
                }
            }
            // Each run's glyphs up to there.
            for run in line.indices where run <= glyphs[last].run {
                let count = run < glyphs[last].run ? line[run].count : glyphs[last].glyph + 1
                ctx.draw(line[run][0..<count])
            }
            let baseline = ellipsis.firstBaseline(in: size)
            ctx.draw(ellipsis, in: CGRect(x: end(last), y: line.origin.y - baseline, width: size.width, height: size.height))
        }

        /// Whether glyph `index` of `run` is a space between words, its character counted from `start`.
        private func isSpace(_ run: Text.Layout.Run, _ index: Int, from start: Text.Layout.CharacterIndex?) -> Bool {
            let indices = run.characterIndices
            guard let start, indices.indices.contains(index) else { return false }
            let offset = start.distance(to: indices[index])
            guard characters.indices.contains(offset), let scalar = Unicode.Scalar(characters[offset]) else { return false }
            return scalar.properties.isWhitespace
        }
    }

    /// Measured from the TV app's show page at 1080p.
    struct Metrics {
        static let stillSize = CGSize(width: 410, height: 230)
        static let cornerRadius: CGFloat = 12
        static let focusedScale: CGFloat = 1.12
        /// How far the still reaches below its frame with focus, growing about its middle.
        static var stillGrowth: CGFloat { stillSize.height * (focusedScale - 1) / 2 }
        static let shadowOpacity = 0.4
        static let shadowRadius: CGFloat = 20
        static let shadowOffset: CGFloat = 12
        static let textSpacing: CGFloat = 22
        static let textInset: CGFloat = 18
        static let textHeight: CGFloat = 270
        static let focusedTextHeight: CGFloat = 320
        /// The still grown, the gap, and the text as tall as it is with focus.
        static var height: CGFloat { stillSize.height + stillGrowth + textSpacing - textInset + focusedTextHeight }
        static let lineSpacing: CGFloat = 6
        static let overviewLineLimit = 3
        static let focusedOverviewLineLimit = 5
        /// How far a line can reach past the synopsis's space and still count as in it, for rounding.
        nonisolated static let lineTolerance: CGFloat = 0.5
        /// How close to showing all or none of a line counts as that, so a line at rest never shows
        /// faintly.
        nonisolated static let fadeSnap: CGFloat = 0.05
        static let platterOpacity = 0.1
        static let platterCornerRadius: CGFloat = 16
        static let dimOpacity = 0.6
        static let dimmestOpacity = 0.5
        static let playInfoSpacing: CGFloat = 10
        static let playInfoInset: CGFloat = 16
        static let playInfoShadowOpacity = 0.5
        static let playInfoShadowRadius: CGFloat = 6
        static let barWidth: CGFloat = 40
        static let barHeight: CGFloat = 5
        static let barTrackOpacity = 0.4
        /// Each a size smaller than the TV app's, to fit the tags.
        static var numberFont: Font { .system(size: 19, weight: .semibold) }
        static var nameFont: Font { .body.weight(.medium) }
        static var textFont: Font { .caption2 }
        static var tagFont: Font { .system(size: 15, weight: .bold) }
        static let tagSpacing: CGFloat = 6
        static let tagOpacity = 0.75
        static let ratingPadding: CGFloat = 5
        static let ratingCornerRadius: CGFloat = 4
        static let ratingLineWidth: CGFloat = 1.5
        static var focusMotion: Animation { .easeOut(duration: 0.2) }
    }
}
