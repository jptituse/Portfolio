import Foundation
import JellyfinAPI
import PortfolioShared

extension JellyfinServerClient {
    /// Where `item` plays from: its default version, sent as the file it is (direct play), for
    /// `session`'s user. The server's sign-in header goes with every request for it.
    ///
    /// - Throws: `JellyfinError.cannotPlayDirectly` if the server won't send the default version as
    ///   it is; `.unauthorized` if the server no longer accepts the session, `.unreachable` or
    ///   `.serverError`; `CancellationError` if the task is cancelled.
    // FIXME: Fall back to a transcode, and offer the item's other versions (roadmap 3.2, no issue yet).
    public func playbackSource(for item: MediaItem, session: UserSession) async throws -> PlaybackSource {
        let request = PlaybackInfoDto(
            deviceProfile: Self.deviceProfile,
            enableDirectPlay: true,
            enableDirectStream: false,
            enableTranscoding: false,
            maxStreamingBitrate: Self.maxBitrate,
            userID: session.user.id
        )
        let info = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.getPostedPlaybackInfo(itemID: item.id, request)).value
        }
        // The server lists the default version first.
        guard let source = info.mediaSources?.first, source.isSupportsDirectPlay == true, let sourceID = source.id else {
            throw JellyfinError.cannotPlayDirectly
        }
        guard let url = Self.streamURL(for: item.id, sourceID: sourceID, playSessionID: info.playSessionID, on: session.server) else {
            throw JellyfinError.serverError(statusCode: nil)
        }
        return PlaybackSource(
            url: url,
            httpHeaders: ["Authorization": identity.authorizationHeader(accessToken: session.accessToken)],
            versionID: sourceID,
            playSessionID: info.playSessionID
        )
    }

    /// Tells the server `item` started playing from `source` at `position`, played as it is, so it
    /// shows among the user's sessions.
    ///
    /// - Throws: as `playbackSource(for:session:)`, but `cannotPlayDirectly`.
    public func reportPlaybackStarted(of item: MediaItem, from source: PlaybackSource, at position: Duration, session: UserSession) async throws {
        let report = PlaybackStateInfo(
            canSeek: true,
            isPaused: false,
            itemID: item.id,
            mediaSourceID: source.versionID,
            playMethod: .directPlay,
            playSessionID: source.playSessionID,
            positionTicks: position.ticks
        )
        _ = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.reportPlaybackStart(report))
        }
    }

    /// Tells the server `item` stopped playing at `position`, so it saves where the user got to, and
    /// marks it watched if that's near enough the end.
    ///
    /// - Throws: as `reportPlaybackStarted(of:from:at:session:)`.
    public func reportPlaybackStopped(of item: MediaItem, from source: PlaybackSource, at position: Duration, session: UserSession) async throws {
        let report = PlaybackStopInfo(
            itemID: item.id,
            mediaSourceID: source.versionID,
            playSessionID: source.playSessionID,
            positionTicks: position.ticks
        )
        _ = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.reportPlaybackStopped(report))
        }
    }

    /// Where the server sends a version of an item as the file it is (`static`).
    static func streamURL(for itemID: String, sourceID: String, playSessionID: String?, on server: ServerInfo) -> URL? {
        guard var components = URLComponents(url: server.url.appending(path: "Videos/\(itemID)/stream"), resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "mediaSourceId", value: sourceID),
        ] + (playSessionID.map { [URLQueryItem(name: "playSessionId", value: $0)] } ?? [])
        return components.url
    }

    /// What the app plays as it is: the containers and codecs AetherEngine handles, at any bitrate, with
    /// subtitles in the file left to the player. It asks for no transcodes.
    static var deviceProfile: DeviceProfile {
        DeviceProfile(
            directPlayProfiles: [
                DirectPlayProfile(
                    audioCodec: Self.audioCodecs.joined(separator: ","),
                    container: Self.containers.joined(separator: ","),
                    type: .video,
                    videoCodec: Self.videoCodecs.joined(separator: ",")
                ),
            ],
            maxStaticBitrate: Self.maxBitrate,
            maxStreamingBitrate: Self.maxBitrate,
            name: "Portfolio",
            subtitleProfiles: Self.subtitleFormats.map { SubtitleProfile(format: $0, method: .embed) }
        )
    }

    /// High enough for any remux: the server's own limits for the user still apply.
    static let maxBitrate = 400_000_000

    /// AetherEngine's containers, as Jellyfin names them.
    static let containers = ["mp4", "m4v", "mov", "3gp", "3g2", "mkv", "webm", "ts", "mts", "m2ts", "mpegts", "mpeg", "mpg", "vob", "avi", "asf", "wmv", "ogg", "ogv", "flv", "rm", "rmvb"]
    static let videoCodecs = ["h264", "hevc", "av1", "vp9", "vp8", "mpeg2video", "mpeg1video", "mpeg4", "msmpeg4v3", "vc1", "wmv3", "h263", "theora"]
    static let audioCodecs = [
        "aac", "ac3", "eac3", "flac", "alac", "truehd", "mlp", "dts", "mp3", "mp2", "opus", "vorbis",
        "pcm_s16le", "pcm_s24le", "pcm_s16be", "pcm_s24be", "pcm_f32le", "wmav2", "wmapro", "wmalossless",
    ]
    static let subtitleFormats = ["srt", "subrip", "ass", "ssa", "vtt", "webvtt", "mov_text", "pgssub", "dvdsub", "dvbsub"]
}
