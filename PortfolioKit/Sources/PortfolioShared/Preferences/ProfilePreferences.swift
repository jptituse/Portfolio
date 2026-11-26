import Foundation
import Observation

/// One profile's own settings, kept in `UserDefaults` under the profile: what Home's banner shows, the
/// streaming quality and languages to play in, skipping, and spoilers. What each affects reads it when
/// it needs it.
///
/// Some are kept before what reads them is built: the streaming quality, languages, skip times and
/// buttons are read by the player once it does each.
@MainActor
@Observable
public final class ProfilePreferences {
    /// What Home's banner goes through.
    public var hero: Hero {
        didSet { save(hero, Key.hero) }
    }
    /// The least a stream may be sent at, in bits per second, or nil for no least.
    public var minimumStreamingBitrate: Int? {
        didSet { save(minimumStreamingBitrate, Key.minimumStreamingBitrate) }
    }
    /// The most a stream may be sent at, in bits per second, or nil for the file's own. Only kept with a
    /// minimum.
    public var maximumStreamingBitrate: Int? {
        didSet { save(maximumStreamingBitrate, Key.maximumStreamingBitrate) }
    }
    /// The language to play audio in, or nil for the account's own preference on its server, else the
    /// original language.
    public var audioLanguage: AudioLanguage? {
        didSet { save(audioLanguage, Key.audioLanguage) }
    }
    /// The language to show subtitles in, as an ISO 639-2 code, or nil for the account's own preference
    /// on its server, else English.
    public var subtitleLanguage: String? {
        didSet { save(subtitleLanguage, Key.subtitleLanguage) }
    }
    /// How far clicking Right skips.
    public var skipForward: Duration {
        didSet { save(skipForward, Key.skipForward) }
    }
    /// How far clicking Left skips.
    public var skipBack: Duration {
        didSet { save(skipBack, Key.skipBack) }
    }
    /// What happens at each kind of segment the server marks, such as an intro.
    public var segmentSkipping: [MediaSegmentKind: SegmentSkipping] {
        didSet { save(segmentSkipping, Key.segmentSkipping) }
    }
    /// What happens at an episode's credits.
    public var credits: CreditsSkipping {
        didSet { save(credits, Key.credits) }
    }
    /// Whether to blur the stills of episodes not watched yet and hide what happens in them.
    public var hidesSpoilers: Bool {
        didSet { save(hidesSpoilers, Key.hidesSpoilers) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let prefix: String

    public init(profile: ProfileID, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let prefix = "profiles/\(profile.serverID)/\(profile.userID)/"
        self.prefix = prefix
        func load<Value: Decodable>(_ key: String, or fallback: Value) -> Value {
            defaults.decoded(forKey: prefix + key, or: fallback)
        }
        hero = load(Key.hero, or: .recentlyAdded)
        minimumStreamingBitrate = load(Key.minimumStreamingBitrate, or: nil)
        maximumStreamingBitrate = load(Key.maximumStreamingBitrate, or: nil)
        audioLanguage = load(Key.audioLanguage, or: nil)
        subtitleLanguage = load(Key.subtitleLanguage, or: nil)
        skipForward = load(Key.skipForward, or: Self.defaultSkip)
        skipBack = load(Key.skipBack, or: Self.defaultSkip)
        segmentSkipping = load(Key.segmentSkipping, or: [:])
        credits = load(Key.credits, or: .upNext)
        hidesSpoilers = load(Key.hidesSpoilers, or: false)
    }

    /// What happens at a kind of segment: shows a button to skip it unless it's been chosen otherwise.
    public func skipping(_ kind: MediaSegmentKind) -> SegmentSkipping {
        segmentSkipping[kind] ?? .button
    }

    public func setSkipping(_ skipping: SegmentSkipping, for kind: MediaSegmentKind) {
        segmentSkipping[kind] = skipping
    }

    /// How far a click skips unless it's been chosen otherwise.
    public static let defaultSkip = Duration.seconds(30)

    private func save<Value: Encodable>(_ value: Value, _ key: String) {
        defaults.setEncoded(value, forKey: prefix + key)
    }

    private enum Key {
        static let hero = "hero"
        static let minimumStreamingBitrate = "minimumStreamingBitrate"
        static let maximumStreamingBitrate = "maximumStreamingBitrate"
        static let audioLanguage = "audioLanguage"
        static let subtitleLanguage = "subtitleLanguage"
        static let skipForward = "skipForward"
        static let skipBack = "skipBack"
        static let segmentSkipping = "segmentSkipping"
        static let credits = "credits"
        static let hidesSpoilers = "hidesSpoilers"
    }
}

/// The language to play audio in.
public enum AudioLanguage: Hashable, Sendable, Codable {
    /// The language it was made in, whatever that is.
    case original
    /// A language, by its ISO 639-2 code, such as "eng".
    case language(String)
}

extension ProfilePreferences {
    /// What Home's banner goes through: the newest items, or those of a collection or playlist the
    /// profile picked, kept with its name to show without asking the server.
    public enum Hero: Hashable, Sendable, Codable {
        case recentlyAdded
        case collection(id: String, name: String)
        case playlist(id: String, name: String)
    }
}

/// A kind of part of an episode or film that a server can mark, to skip.
public enum MediaSegmentKind: String, Hashable, Sendable, Codable, CaseIterable, CodingKeyRepresentable {
    case intro
    case recap
    /// A preview of the next episode.
    case preview
    case commercial
}

/// What happens when playback reaches a segment it can skip.
public enum SegmentSkipping: String, Hashable, Sendable, Codable, CaseIterable {
    /// Nothing: it plays.
    case off
    /// A button offers to skip it.
    case button
    /// It's skipped.
    case automatic
}

/// What happens when playback reaches an episode's credits.
public enum CreditsSkipping: String, Hashable, Sendable, Codable, CaseIterable {
    /// Nothing: they play.
    case off
    /// A button counts down to the next episode and plays it, or offers to skip the credits where a
    /// scene follows them.
    case upNext
    /// The next episode plays at once, or the credits are skipped where a scene follows them.
    case automatic
}
