/// Where playback was as AetherEngine rebuilds itself at the playhead, as it does for another audio track
/// or Reduce Loud Sounds: it reopens the file there, its clock reading zero until it's open again, and
/// the player's bar went back to the start meanwhile. The time shown stays where playback was until the
/// clock is back.
struct RebuildHold: Equatable {
    let position: Duration
    /// Whether the clock has gone back for the rebuild.
    private(set) var hasStopped = false

    init(at position: Duration) {
        self.position = position
    }

    /// Whether the clock reading `time` is where playback is again: back where it was once the rebuild
    /// has stopped it, or moving on from there without one.
    mutating func isOver(at time: Duration) -> Bool {
        if time < position - Self.tolerance {
            hasStopped = true
            return false
        }
        return hasStopped || time > position + Self.tolerance
    }

    /// How far from where it was the rebuild can reopen it.
    static let tolerance = Duration.seconds(2)
    /// How long a hold lasts at most, should the clock never come back.
    static let timeout = Duration.seconds(10)
}
