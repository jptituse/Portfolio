import Foundation
import Observation

/// One profile's own settings, kept in `UserDefaults` under the profile: what Home's banner shows, the
/// streaming quality and languages to play in, skipping, and spoilers, and how each item played last.
/// What each affects reads it when it needs it.
///
/// **How an item played last** is kept for its group, an episode's show, so changing it for one of the
/// group's items changes it for them all. A movie, in no group, keeps its own.
///
/// Some are kept before what reads them is built: the skip buttons are read by the player once it shows
/// them.
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
    /// The profile's own ratings of items, half a star to 5 stars in halves, by item. Kept on this
    /// device only.
    public private(set) var ratings: [String: Double] {
        didSet { save(ratings, Key.ratings) }
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
        ratings = load(Key.ratings, or: [:])
    }

    /// How many stars the profile gave `item`, if it rated it: 0.5 to 5, in halves.
    public func rating(of item: MediaItem) -> Double? {
        ratings[item.id]
    }

    /// Rates `item` half a star to 5 stars, to the nearest half, or takes its rating back: nil, or no
    /// stars at all.
    public func rate(_ item: MediaItem, stars: Double?) {
        let halves = stars.map { min(10, max(0, ($0 * 2).rounded())) }
        ratings[item.id] = halves.flatMap { $0 > 0 ? $0 / 2 : nil }
    }

    /// What happens at a kind of segment: shows a button to skip it unless it's been chosen otherwise.
    public func skipping(_ kind: MediaSegmentKind) -> SegmentSkipping {
        segmentSkipping[kind] ?? .button
    }

    public func setSkipping(_ skipping: SegmentSkipping, for kind: MediaSegmentKind) {
        segmentSkipping[kind] = skipping
    }

    /// How far a click skips unless it's been chosen otherwise.
    public nonisolated static let defaultSkip = Duration.seconds(30)

    /// Whether `item`'s subtitles show as the file has them (Style's Original): as it, or its group, played
    /// last, else not.
    public func showsOriginalSubtitles(for item: MediaItem) -> Bool {
        played(Key.originalSubtitles, for: item) ?? false
    }

    public func setShowsOriginalSubtitles(_ original: Bool, for item: MediaItem) {
        setPlayed(original, Key.originalSubtitles, for: item)
    }

    /// How `item`, or its group, played last, as `setting` names it.
    private func played<Value: Codable>(_ setting: String, for item: MediaItem) -> Value? {
        defaults.decoded(Value?.self, forKey: prefix + Self.key(setting, for: item), or: nil)
    }

    /// Keeps `value` for `item`, or its group.
    private func setPlayed<Value: Codable>(_ value: Value, _ setting: String, for item: MediaItem) {
        defaults.setEncoded(value, forKey: prefix + Self.key(setting, for: item))
    }

    /// Where `setting` is kept for `item`: under its group, an episode's show, else under itself.
    private static func key(_ setting: String, for item: MediaItem) -> String {
        item.episode?.seriesID.map { Key.group($0, setting) } ?? Key.item(item.id, setting)
    }

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
        static let ratings = "ratings"
        static let originalSubtitles = "originalSubtitles"
        static func item(_ id: String, _ setting: String) -> String { "items/\(id)/\(setting)" }
        static func group(_ id: String, _ setting: String) -> String { "groups/\(id)/\(setting)" }
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
