import AetherEngine
import Foundation
import PortfolioShared

/// Which of AetherEngine's tracks a server's track is.
///
/// A server numbers a version's streams its own way: Jellyfin puts subtitle and audio files beside the
/// media first, and skips streams it leaves out, such as a file's fonts. AetherEngine numbers a file's
/// streams as the file does. Both list a file's streams in the file's order, though, so a track in the
/// stream is the engine's track at the same place among those of its kind: audio, subtitles drawn as
/// text, or subtitles drawn as pictures. Subtitle files are numbered from
/// `AetherEngine.externalSubtitleTrackIDBase`, in the order they're handed to the engine.
@MainActor
enum TrackNumbering {
    /// The subtitles in files of their own, in the order the engine is given them.
    static func subtitleFiles(in source: PlaybackSource) -> [(track: MediaTrack, url: URL)] {
        source.subtitleTracks.compactMap { track in
            guard case .file(let url) = track.delivery else { return nil }
            return (track, url)
        }
    }

    /// The engine's number for `track` of `source`, among the engine's `audio` and `subtitles`, or nil
    /// if the engine doesn't have it.
    static func engineTrackID(for track: MediaTrack, in source: PlaybackSource, audio: [TrackInfo], subtitles: [TrackInfo]) -> Int? {
        switch track.delivery {
        case .file:
            guard let place = subtitleFiles(in: source).firstIndex(where: { $0.track.id == track.id }) else { return nil }
            return AetherEngine.externalSubtitleTrackIDBase + place
        case .transcoded:
            return nil
        case .inStream:
            let isAudio = source.audioTracks.contains { $0.id == track.id }
            let kind = isAudio ? Kind.audio : track.isText ? .text : .pictures
            let serverTracks = (isAudio ? source.audioTracks : source.subtitleTracks)
                .filter { $0.delivery == .inStream && (isAudio || ($0.isText ? Kind.text : .pictures) == kind) }
            let engineTracks = (isAudio ? audio : subtitles)
                .filter { !$0.isExternal && $0.id < AetherEngine.externalSubtitleTrackIDBase && (isAudio || Kind(subtitleCodec: $0.codec) == kind) }
                .sorted { $0.id < $1.id }
            guard let place = serverTracks.firstIndex(where: { $0.id == track.id }), place < engineTracks.count else { return nil }
            return engineTracks[place].id
        }
    }

    private enum Kind {
        case audio, text, pictures, other

        /// What kind of subtitles a codec, as libavcodec names it, draws. Closed captions carried in the
        /// video and teletext aren't streams a server lists.
        init(subtitleCodec codec: String) {
            let codec = codec.lowercased()
            if ["eia_608", "eia_708", "cea708", "cea_708", "teletext", "dvb_teletext"].contains(where: { codec.contains($0) }) {
                self = .other
            } else if ["pgs", "hdmv", "dvb_sub", "dvbsub", "dvd_sub", "dvdsub", "vobsub", "xsub"].contains(where: { codec.contains($0) }) {
                self = .pictures
            } else {
                self = .text
            }
        }
    }
}
