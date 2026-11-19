import Foundation

/// The signed-in user's state for an item.
public struct UserData: Hashable, Sendable {
    public let isPlayed: Bool
    public let isFavorite: Bool
    /// Where playback was left off. Zero when there's nothing to resume.
    public let playbackPosition: Duration
    public let playCount: Int
    /// When the user last started playing it, anywhere: a server stamps it as playback starts.
    public let lastPlayed: Date?

    public init(isPlayed: Bool = false, isFavorite: Bool = false, playbackPosition: Duration = .zero, playCount: Int = 0, lastPlayed: Date? = nil) {
        self.isPlayed = isPlayed
        self.isFavorite = isFavorite
        self.playbackPosition = playbackPosition
        self.playCount = playCount
        self.lastPlayed = lastPlayed
    }

    /// Whether there's somewhere to resume from.
    public var canResume: Bool {
        playbackPosition > .zero
    }
}
