import Observation
import PortfolioShared

/// The user's state for items, as the server had it after they played here: newer than what the items
/// were loaded with, until they're loaded again. Cards show the newer of the two, so the card Back lands
/// on after playing offers to resume from where playback stopped, without loading its row again, which
/// would rebuild the row around it.
///
/// Whichever was played last wins (`UserData.lastPlayed`, which the server stamps as playback starts),
/// so an item loaded again after playing somewhere else shows that.
@MainActor
@Observable
public final class UserDataUpdates {
    private var updates: [MediaItem.ID: UserData] = [:]

    public init() {}

    /// The newest state known for `item`: its update, unless it was loaded after that.
    public func userData(for item: MediaItem) -> UserData {
        guard let update = updates[item.id] else { return item.userData }
        let loaded = item.userData.lastPlayed ?? .distantPast
        return (update.lastPlayed ?? .distantPast) >= loaded ? update : item.userData
    }

    /// Records the user's state for an item, as the server has it after playing it.
    public func update(_ userData: UserData, for item: MediaItem.ID) {
        updates[item] = userData
    }
}
