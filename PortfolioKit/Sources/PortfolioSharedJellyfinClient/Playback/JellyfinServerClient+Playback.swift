import Foundation
import Get
import JellyfinAPI
import PortfolioShared

extension JellyfinServerClient {
    /// Where `item` plays from, for `session`'s user, as `request` asks: its default version unless it
    /// names another, sent as the file it is (direct play) wherever the server will, and otherwise as a
    /// stream the server makes (a transcode), with the version's tracks and which of them it starts on.
    /// The server's sign-in header goes with every request for it.
    ///
    /// Asked to play the original, it plays the file as it is even where the server would make a stream,
    /// such as above the server's limit for connections from outside its network: the server sends any
    /// file as it is when asked (`static`), whatever `PlaybackInfo` decided. Its tracks are then the
    /// file's, and what only a stream could carry (subtitles drawn as pictures from a file of their own,
    /// audio in a file of its own) is left out.
    ///
    /// - Throws: `JellyfinError.cannotPlay` if the server will send it neither way; `.unauthorized` if
    ///   the server no longer accepts the session, `.unreachable` or `.serverError`; `CancellationError`
    ///   if the task is cancelled.
    // FIXME: Offer the item's other versions (roadmap 3.2, no issue yet).
    public func playbackSource(for item: MediaItem, _ request: PlaybackRequest = PlaybackRequest(), session: UserSession) async throws -> PlaybackSource {
        let body = PlaybackInfoDto(
            audioStreamIndex: request.audioTrack,
            deviceProfile: Self.deviceProfile,
            enableDirectPlay: true,
            enableDirectStream: true,
            enableTranscoding: true,
            maxStreamingBitrate: request.maxBitrate ?? Self.maxBitrate,
            mediaSourceID: request.versionID,
            startTimeTicks: request.startPosition > .zero ? request.startPosition.ticks : nil,
            subtitleStreamIndex: request.subtitles.map(Self.subtitleStreamIndex),
            userID: session.user.id
        )
        let info = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.getPostedPlaybackInfo(itemID: item.id, body)).value
        }
        // The server lists the default version first.
        let versions = info.mediaSources ?? []
        guard let version = request.versionID.flatMap({ id in versions.first { $0.id == id } }) ?? versions.first,
            let versionID = version.id else {
            throw JellyfinError.cannotPlay
        }
        // The file as it is, where the server would rather make a stream: the tracks the server describes
        // are as that stream would carry them.
        let playsFileAnyway = version.isSupportsDirectPlay != true && request.playsOriginal
        let method: PlaybackSource.Method
        let url: URL?
        if version.isSupportsDirectPlay == true || playsFileAnyway {
            method = .directPlay
            url = Self.streamURL(for: item.id, sourceID: versionID, playSessionID: info.playSessionID, on: session.server)
        } else if let transcodingURL = version.transcodingURL {
            method = .transcode
            url = Self.url(for: transcodingURL, on: session.server)
        } else {
            throw JellyfinError.cannotPlay
        }
        guard let url else { throw JellyfinError.serverError(statusCode: nil) }
        let streams = (version.mediaStreams ?? []).sorted { ($0.index ?? 0) < ($1.index ?? 0) }
        let audioTracks = streams.filter { $0.type == .audio }.compactMap(Self.audioTrack)
            .filter { !playsFileAnyway || $0.delivery == .inStream }
        let subtitleTracks = streams.filter { $0.type == .subtitle }
            .compactMap { Self.subtitleTrack($0, playingFile: playsFileAnyway, on: session.server) }
        // What the server picked may be one left out.
        let audioTrack = version.defaultAudioStreamIndex.flatMap { id in
            audioTracks.contains { $0.id == id } ? id : (audioTracks.first(where: \.isDefault) ?? audioTracks.first)?.id
        }
        let subtitleTrack = version.defaultSubtitleStreamIndex.flatMap { id in subtitleTracks.contains { $0.id == id } ? id : nil }
        return PlaybackSource(
            url: url,
            httpHeaders: ["Authorization": identity.authorizationHeader(accessToken: session.accessToken)],
            versionID: versionID,
            playSessionID: info.playSessionID,
            method: method,
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks,
            audioTrack: audioTrack,
            subtitleTrack: subtitleTrack,
            bitrate: version.bitrate
        )
    }

    /// Tells the server to stop making `source`'s stream, once the player has moved on from it, as
    /// Jellyfin's web client does. A file played as it is needs nothing.
    ///
    /// - Throws: as `reportPlaybackStarted(of:from:at:session:)`.
    public func stopTranscoding(_ source: PlaybackSource, session: UserSession) async throws {
        guard source.method == .transcode, let playSessionID = source.playSessionID else { return }
        let request = Request<Void>(
            path: "/Videos/ActiveEncodings",
            method: .delete,
            query: [("deviceId", identity.deviceID), ("playSessionId", playSessionID)]
        )
        _ = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken).send(request)
        }
    }

    /// Tells the server `item` started playing from `source` at `position`, so it shows among the user's
    /// sessions, with how it's sent and which tracks are playing. The server stamps the item as last
    /// played now.
    ///
    /// - Throws: as `playbackSource(for:_:session:)`, but `cannotPlay`.
    public func reportPlaybackStarted(of item: MediaItem, from source: PlaybackSource, at position: Duration, session: UserSession) async throws {
        let report = Self.playbackState(of: item, from: source, at: position, isPaused: false)
        _ = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.reportPlaybackStart(report))
        }
    }

    /// Tells the server where playback of `item` is, whether it's paused, and which tracks are playing,
    /// as it plays. The server saves the position each time, so it isn't lost if playback never reports
    /// stopping, and the tracks, to start on them next time if the user has it remember them.
    ///
    /// - Throws: as `reportPlaybackStarted(of:from:at:session:)`.
    public func reportPlaybackProgress(of item: MediaItem, from source: PlaybackSource, at position: Duration, isPaused: Bool, session: UserSession) async throws {
        let report = Self.playbackState(of: item, from: source, at: position, isPaused: isPaused)
        _ = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.reportPlaybackProgress(report))
        }
    }

    /// The user's state for `item` as the server has it now, such as where they got to, wherever
    /// they played it.
    ///
    /// - Throws: `JellyfinError.unauthorized` if the server no longer accepts the session,
    ///   `.unreachable` or `.serverError`; `CancellationError` if the task is cancelled.
    public func userData(for item: MediaItem, session: UserSession) async throws -> UserData {
        let data = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.getItemUserData(itemID: item.id, userID: session.user.id)).value
        }
        return UserData(data)
    }

    /// Tells the server `item` stopped playing at `position`, so it saves where the user got to, and
    /// marks it watched if that's near enough the end. It also stops any stream it was making.
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

    private static func playbackState(of item: MediaItem, from source: PlaybackSource, at position: Duration, isPaused: Bool) -> PlaybackStateInfo {
        PlaybackStateInfo(
            audioStreamIndex: source.audioTrack,
            canSeek: true,
            isPaused: isPaused,
            itemID: item.id,
            mediaSourceID: source.versionID,
            playMethod: source.method == .directPlay ? .directPlay : .transcode,
            playSessionID: source.playSessionID,
            positionTicks: position.ticks,
            // Jellyfin's number for subtitles off.
            subtitleStreamIndex: source.subtitleTrack ?? -1
        )
    }

    /// Jellyfin's number for `subtitles`: -1 for none.
    private static func subtitleStreamIndex(_ subtitles: PlaybackRequest.Subtitles) -> Int {
        switch subtitles {
        case .off: -1
        case .track(let id): id
        }
    }

    /// An audio stream as a track. Audio in a file of its own only plays in a stream the server makes.
    static func audioTrack(_ stream: MediaStream) -> MediaTrack? {
        guard let index = stream.index else { return nil }
        return MediaTrack(
            id: index,
            title: stream.displayTitle ?? stream.title ?? stream.language ?? "Track \(index + 1)",
            language: stream.language,
            isDefault: stream.isDefault ?? false,
            isForced: stream.isForced ?? false,
            isText: false,
            delivery: stream.isExternal == true ? .transcoded : .inStream
        )
    }

    /// A subtitle stream as a track, delivered as the server says it would be for this device and this
    /// way of sending the media. The server leaves out what it would drop.
    ///
    /// Played as the file it is where the server would make a stream (`playingFile`), it's delivered as
    /// the file has it instead: in the file, or a text file of its own the server sends. Pictures in a file
    /// of their own only come drawn into a stream, so they're left out.
    static func subtitleTrack(_ stream: MediaStream, playingFile: Bool = false, on server: ServerInfo) -> MediaTrack? {
        guard let index = stream.index else { return nil }
        let delivery: MediaTrack.Delivery
        switch stream.deliveryMethod {
        case _ where playingFile && stream.isExternal != true:
            delivery = .inStream
        case .embed, .hls:
            delivery = .inStream
        case .external:
            guard let path = stream.deliveryURL else { return nil }
            let url = stream.isExternalURL == true ? URL(string: path) : url(for: path, on: server)
            delivery = url.map(MediaTrack.Delivery.file) ?? .transcoded
        case .drop:
            return nil
        case .encode, nil:
            delivery = .transcoded
        }
        if playingFile, delivery == .transcoded { return nil }
        return MediaTrack(
            id: index,
            title: stream.displayTitle ?? stream.title ?? stream.language ?? "Track \(index + 1)",
            language: stream.language,
            isDefault: stream.isDefault ?? false,
            isForced: stream.isForced ?? false,
            isText: stream.isTextSubtitleStream ?? true,
            delivery: delivery
        )
    }

    /// A path the server gave, such as a transcode's or a subtitle file's, on `server`, which may itself
    /// sit under a path.
    static func url(for path: String, on server: ServerInfo) -> URL? {
        let base = server.url.absoluteString
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        return URL(string: trimmed + (path.hasPrefix("/") ? path : "/" + path))
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
    /// subtitles in the file left to the player, and text subtitles in files of their own fetched by it.
    /// Anything else, or a stream slower than the file, the server makes as HLS, which AetherEngine hands
    /// to AVPlayer: HEVC or H.264 in fragmented MP4, so a stream it only has to repackage keeps HEVC
    /// (and Dolby Vision's base layer), with the audio AVPlayer plays. Subtitles that need a picture
    /// drawn, the server draws into it.
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
                + Self.subtitleFileFormats.map { SubtitleProfile(format: $0, method: .external) },
            transcodingProfiles: [
                TranscodingProfile(
                    protocol: .hls,
                    audioCodec: Self.streamAudioCodecs.joined(separator: ","),
                    container: "mp4",
                    context: .streaming,
                    isBreakOnNonKeyFrames: true,
                    maxAudioChannels: "8",
                    minSegments: 2,
                    type: .video,
                    videoCodec: Self.streamVideoCodecs.joined(separator: ",")
                ),
            ]
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
    /// The text subtitles AetherEngine reads from a file of their own, the first the server converts
    /// others to.
    static let subtitleFileFormats = ["srt", "ass", "ssa", "vtt"]
    /// What AVPlayer plays in a stream the server makes, the first what it encodes to.
    static let streamVideoCodecs = ["hevc", "h264"]
    static let streamAudioCodecs = ["aac", "ac3", "eac3", "alac", "flac"]
}
