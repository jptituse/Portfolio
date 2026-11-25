import AetherEngine
import PortfolioSharedPlaybackEngine
import SwiftUI

/// The subtitles showing, over the picture: text centered near the picture's bottom (or its top, where
/// a cue asks), in the user's caption style or as the file has it (`drawsOriginalSubtitles`), and
/// pictures where the disc puts them. They all rise above whatever covers the bottom
/// (`subtitlesBottomInset`), such as a player's controls.
struct SubtitlesView: View {
    let viewModel: SubtitlesViewModel

    @Environment(\.subtitlesBottomInset) private var bottomInset
    @Environment(\.drawsOriginalSubtitles) private var drawsOriginal

    var body: some View {
        GeometryReader { proxy in
            let video = viewModel.videoRect(in: proxy.size)
            let lines = viewModel.lines(keepingColors: drawsOriginal)
            let lowest = video.maxY - video.height * Metrics.edgeMargin
            ZStack(alignment: .topLeading) {
                ForEach(lines) { line in
                    if case .image(let image, let position, let canvas) = line.content {
                        let frame = SubtitlesViewModel.imageRect(position: position, canvas: canvas, in: video)
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
                text(lines.filter { !$0.isAtTop }, in: video, alignment: .bottom)
                text(lines.filter(\.isAtTop), in: video, alignment: .top)
            }
            .offset(y: -max(0, lowest - (proxy.size.height - bottomInset)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The text cues of `lines`, one under another, inside `video` at `alignment`.
    @ViewBuilder private func text(_ lines: [SubtitlesViewModel.Line], in video: CGRect, alignment: Alignment) -> some View {
        let texts = lines.compactMap { line -> (id: Int, text: AttributedString)? in
            guard case .text(let text) = line.content else { return nil }
            return (line.id, text)
        }
        if !texts.isEmpty {
            CaptionTextView(lines: texts.map(\.text), style: drawsOriginal ? .original : viewModel.style, size: viewModel.fontSize(forVideoHeight: video.height))
                .frame(maxWidth: video.width * Metrics.widthShare)
                .padding(alignment == .bottom ? .bottom : .top, video.height * Metrics.edgeMargin)
                .frame(width: video.width, height: video.height, alignment: alignment)
                .offset(x: video.minX, y: video.minY)
        }
    }
}

extension SubtitlesView {
    /// In AetherEngine's proportions for the subtitles it draws into a picture itself.
    struct Metrics {
        /// How far above the picture's bottom (or below its top) text sits, as a share of its height.
        static let edgeMargin: CGFloat = 0.06
        /// How much of the picture's width text can take.
        static let widthShare: CGFloat = 0.9
    }
}
