import AetherEngine
import Foundation
import PortfolioShared
import Testing

@testable import PortfolioSharedAetherPlaybackEngine

@MainActor
struct TrackNumberingTests {
    /// A file's streams as AetherEngine numbers them: video, two audio tracks, text, picture and text
    /// subtitles, then a font Jellyfin doesn't list. A subtitle file beside it is registered first.
    let engineAudio = [
        TrackInfo(id: 1, name: "English", codec: "eac3", language: "eng", isDefault: true),
        TrackInfo(id: 2, name: "Spanish", codec: "aac", language: "spa", isDefault: false),
    ]
    let engineSubtitles = [
        TrackInfo(id: 3, name: "English", codec: "subrip", language: "eng", isDefault: false),
        TrackInfo(id: 4, name: "Spanish", codec: "hdmv_pgs_subtitle", language: "spa", isDefault: false),
        TrackInfo(id: 5, name: "French", codec: "subrip", language: "fre", isDefault: false),
        TrackInfo(id: AetherEngine.externalSubtitleTrackIDBase, name: "English SDH", codec: "subrip", language: "eng", isDefault: false, isExternal: true),
    ]

    /// The same file as Jellyfin numbers it: the subtitle file first, then the file's streams, without
    /// the font.
    func source(subtitles: [MediaTrack]? = nil) -> PlaybackSource {
        PlaybackSource(
            url: URL(string: "https://media.test/film.mkv")!,
            audioTracks: [
                MediaTrack(id: 2, title: "English", isText: false),
                MediaTrack(id: 3, title: "Spanish", isText: false),
                MediaTrack(id: 9, title: "Commentary", isText: false, delivery: .transcoded),
            ],
            subtitleTracks: subtitles ?? [
                MediaTrack(id: 0, title: "English SDH", delivery: .file(URL(string: "https://media.test/0.srt")!)),
                MediaTrack(id: 4, title: "English"),
                MediaTrack(id: 5, title: "Spanish", isText: false),
                MediaTrack(id: 6, title: "French"),
            ]
        )
    }

    func engineID(for id: MediaTrack.ID, in source: PlaybackSource) -> Int? {
        let track = (source.audioTracks + source.subtitleTracks).first { $0.id == id }!
        return TrackNumbering.engineTrackID(for: track, in: source, audio: engineAudio, subtitles: engineSubtitles)
    }

    @Test func findsAudioByItsPlaceAmongTheFilesAudio() {
        let source = source()
        #expect(engineID(for: 2, in: source) == 1)
        #expect(engineID(for: 3, in: source) == 2)
    }

    @Test func findsSubtitlesByTheirPlaceAmongTheFilesOfTheirKind() {
        let source = source()
        #expect(engineID(for: 4, in: source) == 3)
        #expect(engineID(for: 5, in: source) == 4)
        #expect(engineID(for: 6, in: source) == 5)
    }

    @Test func numbersSubtitleFilesInTheOrderTheEngineGetsThem() {
        let source = source()
        #expect(TrackNumbering.subtitleFiles(in: source).map(\.track.id) == [0])
        #expect(engineID(for: 0, in: source) == AetherEngine.externalSubtitleTrackIDBase)
    }

    @Test func skipsTheFilesSubtitlesTheServerLeavesOut() {
        // A library set to leave out subtitles drawn as pictures.
        let source = source(subtitles: [MediaTrack(id: 4, title: "English"), MediaTrack(id: 6, title: "French")])
        #expect(engineID(for: 4, in: source) == 3)
        #expect(engineID(for: 6, in: source) == 5)
    }

    @Test func hasNoTrackOnlyTheServersStreamCarries() {
        #expect(engineID(for: 9, in: source()) == nil)
    }
}
