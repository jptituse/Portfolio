import Foundation
import PortfolioShared
import Testing

@testable import PortfolioSharedUI

@MainActor
struct UserDataUpdatesTests {
    let updates = UserDataUpdates()
    let monday = Date(timeIntervalSince1970: 1_800_000_000)
    let tuesday = Date(timeIntervalSince1970: 1_800_086_400)

    func arrival(at position: Duration, lastPlayed: Date?) -> MediaItem {
        MediaItem(id: "arrival", name: "Arrival", kind: .movie, userData: UserData(playbackPosition: position, lastPlayed: lastPlayed))
    }

    @Test func showsAnItemAsItLoadedUntilItsPlayed() {
        let item = arrival(at: .seconds(600), lastPlayed: monday)

        #expect(updates.userData(for: item).playbackPosition == .seconds(600))
    }

    @Test func showsWhereTheUserGotToAfterPlayingAnItemLoadedBefore() {
        let item = arrival(at: .seconds(600), lastPlayed: monday)

        updates.update(UserData(playbackPosition: .seconds(1_500), lastPlayed: tuesday), for: item.id)

        #expect(updates.userData(for: item).playbackPosition == .seconds(1_500))
        #expect(updates.userData(for: arrival(at: .zero, lastPlayed: nil)).playbackPosition == .seconds(1_500))
    }

    @Test func showsAnItemLoadedAfterItPlayedHereAsItLoaded() {
        updates.update(UserData(playbackPosition: .seconds(1_500), lastPlayed: monday), for: "arrival")

        // Played further somewhere else since.
        let item = arrival(at: .seconds(3_000), lastPlayed: tuesday)

        #expect(updates.userData(for: item).playbackPosition == .seconds(3_000))
    }

    @Test func showsWhatItHeardAfterPlayingWhenTheItemLoadedThenToo() {
        let item = arrival(at: .seconds(600), lastPlayed: monday)

        // Played to the end: the server keeps when it started, and resets where it got to.
        updates.update(UserData(isPlayed: true, playbackPosition: .zero, lastPlayed: monday), for: item.id)

        #expect(!updates.userData(for: item).canResume)
        #expect(updates.userData(for: item).isPlayed)
    }
}
