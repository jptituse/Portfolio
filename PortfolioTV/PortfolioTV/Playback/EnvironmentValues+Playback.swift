import PortfolioShared
import PortfolioSharedUI
import SwiftUI

extension EnvironmentValues {
    /// Whether the player is up, from Play until it has gone. Focus can't move to what's under it until
    /// then, so a detail view shown behind it as it closes gets focus once it has.
    @Entry var isPlayerUp = false
    /// Asks where an item plays from ahead of Play, so it starts sooner: once its detail view opens, and
    /// while focus is on something that plays it at once.
    @Entry var preparePlayback = PreparePlaybackAction()
}

/// Asks the open profile's server where an item plays from, ahead of Play. It's equal for the same
/// profile, so the views that read it don't update each time it's set, as they would for a closure.
struct PreparePlaybackAction: Equatable {
    private let profile: CurrentProfileViewModel?

    init(_ profile: CurrentProfileViewModel? = nil) {
        self.profile = profile
    }

    @MainActor func callAsFunction(_ item: MediaItem) {
        profile?.preparePlayback(of: item)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.profile === rhs.profile
    }
}
