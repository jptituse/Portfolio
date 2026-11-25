import AetherEngine
import Foundation
import Observation
import PortfolioSharedPlaybackEngine
import SwiftUI

/// The subtitles showing in an AetherEngine session, and how to draw them: in the user's caption style
/// (`CaptionStyle`), sized and placed as AetherEngine draws them into a picture itself.
///
/// It mirrors the engine's cues and the time of the frame showing. Subtitles AVPlayer draws itself, on a
/// stream the server makes, aren't drawn again.
@MainActor
@Observable
final class SubtitlesViewModel {
    /// A cue showing now, ready to draw.
    struct Line: Identifiable {
        let id: Int
        let content: Content
        /// Whether the cue asks to be at the top of the picture, rather than at its bottom.
        let isAtTop: Bool

        enum Content {
            case text(AttributedString)
            /// A picture, with where it goes, normalized against `canvas` (zero for the video frame).
            case image(CGImage, position: CGRect, canvas: CGSize)
        }
    }

    private var cues: [SubtitleCue] = []
    private var time: Double = 0
    private var activeTrack: Int?
    private var tracks: [TrackInfo] = []
    /// The video's size in pixels, once known, for where its picture sits on screen.
    var videoSize: CGSize?
    private(set) var style = CaptionStyle.current()

    @ObservationIgnored private var mirroring: [Task<Void, Never>] = []

    init(engine: AetherEngine) {
        mirroring = [
            Task { [weak self, engine] in
                for await cues in engine.$subtitleCues.values { self?.cues = cues }
            },
            Task { [weak self, engine] in
                for await seconds in engine.clock.$sourceTime.values { self?.time = seconds }
            },
            Task { [weak self, engine] in
                for await id in engine.$activeSubtitleTrackIndex.values { self?.activeTrack = id }
            },
            Task { [weak self, engine] in
                for await tracks in engine.$subtitleTracks.values { self?.tracks = tracks }
            },
            Task { [weak self] in
                let changes = NotificationCenter.default.notifications(named: CaptionStyle.didChange)
                for await _ in changes.map({ _ in () }) { self?.style = CaptionStyle.current() }
            },
        ]
    }

    isolated deinit {
        mirroring.forEach { $0.cancel() }
    }

    /// The cues showing now, unless AVPlayer draws them itself, with text in the colors the file gives
    /// it if `keepingColors`.
    func lines(keepingColors: Bool) -> [Line] {
        guard tracks.first(where: { $0.id == activeTrack })?.isNativelyRenderedSubtitle != true else { return [] }
        return cues.filter { $0.startTime <= time && time < $0.endTime }.map { Self.line(for: $0, keepingColors: keepingColors) }
    }

    /// Where the picture sits in `size`, filling as much as it can without being cropped.
    func videoRect(in size: CGSize) -> CGRect {
        guard let videoSize, videoSize.width > 0, videoSize.height > 0 else { return CGRect(origin: .zero, size: size) }
        let scale = min(size.width / videoSize.width, size.height / videoSize.height)
        let fitted = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
        return CGRect(x: (size.width - fitted.width) / 2, y: (size.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
    }

    /// The size of subtitle text over a picture `videoHeight` tall, as AetherEngine draws it, before the
    /// caption style scales it.
    func fontSize(forVideoHeight videoHeight: CGFloat) -> CGFloat {
        videoHeight * 0.05
    }

    /// Where a picture cue goes on a picture filling `videoRect`: its position on its canvas, the canvas
    /// laid across the picture's width and centered on it, as AetherEngine places them.
    static func imageRect(position: CGRect, canvas: CGSize, in videoRect: CGRect) -> CGRect {
        guard canvas.width > 0, canvas.height > 0 else {
            return CGRect(
                x: videoRect.minX + position.minX * videoRect.width,
                y: videoRect.minY + position.minY * videoRect.height,
                width: position.width * videoRect.width,
                height: position.height * videoRect.height
            )
        }
        let scale = videoRect.width / canvas.width
        return CGRect(
            x: videoRect.minX + position.minX * canvas.width * scale,
            y: videoRect.midY + (position.minY * canvas.height - canvas.height / 2) * scale,
            width: position.width * canvas.width * scale,
            height: position.height * canvas.height * scale
        )
    }

    static func line(for cue: SubtitleCue, keepingColors: Bool) -> Line {
        let isAtTop = (cue.placement?.alignment).map { (7...9).contains($0) } ?? false
        switch cue.body {
        case .text(let text):
            return Line(id: cue.id, content: .text(AttributedString(text)), isAtTop: isAtTop)
        case .richText(let runs):
            let text = runs.reduce(into: AttributedString()) { text, run in
                var part = AttributedString(run.text)
                if keepingColors, let color = run.color {
                    part.foregroundColor = Color(red: Double(color.r) / 255, green: Double(color.g) / 255, blue: Double(color.b) / 255)
                }
                if run.isUnderlined { part.underlineStyle = .single }
                if run.isStruckThrough { part.strikethroughStyle = .single }
                if run.isBold || run.isItalic {
                    part.inlinePresentationIntent = [run.isBold ? .stronglyEmphasized : [], run.isItalic ? .emphasized : []]
                }
                text += part
            }
            return Line(id: cue.id, content: .text(text), isAtTop: isAtTop)
        case .image(let image):
            return Line(id: cue.id, content: .image(image.cgImage, position: image.position, canvas: image.canvasSize), isAtTop: false)
        }
    }
}
