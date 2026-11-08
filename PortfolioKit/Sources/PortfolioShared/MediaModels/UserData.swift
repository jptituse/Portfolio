/// The signed-in user's state for an item.
public struct UserData: Hashable, Sendable {
    public let isPlayed: Bool
    public let isFavorite: Bool
    /// Where playback was left off. Zero when there's nothing to resume.
    public let playbackPosition: Duration
    public let playCount: Int

    public init(isPlayed: Bool = false, isFavorite: Bool = false, playbackPosition: Duration = .zero, playCount: Int = 0) {
        self.isPlayed = isPlayed
        self.isFavorite = isFavorite
        self.playbackPosition = playbackPosition
        self.playCount = playCount
    }
}
