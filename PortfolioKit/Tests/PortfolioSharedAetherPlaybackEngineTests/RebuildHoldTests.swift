import Testing

@testable import PortfolioSharedAetherPlaybackEngine

struct RebuildHoldTests {
    /// Whether the hold is over at each of `times`, the clock reading them one after another.
    func isOver(_ hold: RebuildHold, at times: [Double]) -> [Bool] {
        var hold = hold
        return times.map { hold.isOver(at: .seconds($0)) }
    }

    @Test func holdsThroughTheRebuildUntilTheClockIsBack() {
        // Still playing for a moment, then reopening the file at zero, then open again near where it was.
        #expect(isOver(RebuildHold(at: .seconds(600)), at: [600.2, 0, 0.5, 599]) == [false, false, false, true])
    }

    @Test func endsWhenPlaybackMovesOnWithoutARebuild() {
        #expect(isOver(RebuildHold(at: .seconds(600)), at: [601, 603]) == [false, true])
    }
}
