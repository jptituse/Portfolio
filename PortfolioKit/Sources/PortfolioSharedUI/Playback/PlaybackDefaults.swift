import PortfolioShared

/// What a player starts on, from the profile's Settings: how fast Auto streams at most, and the languages
/// to play audio and show subtitles in, in place of what the server would pick for the account; and
/// whether Style is Original, as the item, or its show, played last, without which picture subtitles
/// don't show.
public struct PlaybackDefaults: Hashable, Sendable {
    /// The most Auto streams at, in bits per second, or nil to play the file as it is wherever it can.
    public var autoMaxBitrate: Int?
    /// The language to start audio in, or nil for the server's pick.
    public var audioLanguage: AudioLanguage?
    /// The language subtitles show in when they show, or nil for the server's pick.
    public var subtitleLanguage: String?
    /// Whether Style is Original: subtitles as the file has them. Subtitles drawn as pictures (Blu-ray,
    /// DVD, DVB), which nothing can restyle, show only then.
    public var showsOriginalSubtitles: Bool

    public init(
        autoMaxBitrate: Int? = nil,
        audioLanguage: AudioLanguage? = nil,
        subtitleLanguage: String? = nil,
        showsOriginalSubtitles: Bool = false
    ) {
        self.autoMaxBitrate = autoMaxBitrate
        self.audioLanguage = audioLanguage
        self.subtitleLanguage = subtitleLanguage
        self.showsOriginalSubtitles = showsOriginalSubtitles
    }

    /// From the profile's Settings, for `item`.
    @MainActor
    init(_ preferences: ProfilePreferences?, item: MediaItem) {
        self.init(
            autoMaxBitrate: preferences?.maximumStreamingBitrate,
            audioLanguage: preferences?.audioLanguage,
            subtitleLanguage: preferences?.subtitleLanguage,
            showsOriginalSubtitles: preferences?.showsOriginalSubtitles(for: item) ?? false
        )
    }

    /// What a player asks for first.
    var startingRequest: PlaybackRequest {
        PlaybackRequest(maxBitrate: autoMaxBitrate)
    }

    /// The audio track to start on in `source` in place of the server's pick, or nil to keep it: the
    /// track the file marks default for Original, else the first in the language chosen, the one the
    /// file marks default among several. None in that language keeps the server's pick.
    func audioTrack(in source: PlaybackSource) -> MediaTrack.ID? {
        let chosen: MediaTrack? = switch audioLanguage {
        case nil: nil
        case .original: source.audioTracks.first(where: \.isDefault) ?? source.audioTracks.first
        case .language(let code):
            Self.preferred(source.audioTracks.filter { Self.matches($0, code) })
        }
        guard let chosen, chosen.id != source.audioTrack else { return nil }
        return chosen.id
    }

    /// The subtitles to start on in `source` in place of the server's pick, or nil to keep it. Only
    /// subtitles the server would show are changed, to the language chosen, and forced ones it shows,
    /// such as for signs and foreign dialogue, stay. Pictures that can't show are turned off.
    func subtitles(in source: PlaybackSource) -> PlaybackRequest.Subtitles? {
        guard let showing = source.showingSubtitleTrack else { return nil }
        var chosen = showing
        if let code = subtitleLanguage, !showing.isForced, !Self.matches(showing, code),
            let inLanguage = Self.preferred(source.subtitleTracks.filter { track in
                Self.matches(track, code) && !track.isForced && (track.isText || showsOriginalSubtitles)
            }) {
            chosen = inLanguage
        }
        if !chosen.isText, !showsOriginalSubtitles { return .off }
        return chosen.id == showing.id ? nil : .track(chosen.id)
    }

    /// Of several tracks in a language, the one the file marks default, else the first.
    private static func preferred(_ tracks: [MediaTrack]) -> MediaTrack? {
        tracks.first(where: \.isDefault) ?? tracks.first
    }

    private static func matches(_ track: MediaTrack, _ code: String) -> Bool {
        track.language?.caseInsensitiveCompare(code) == .orderedSame
    }
}
