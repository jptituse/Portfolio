import CoreGraphics
import Foundation
import Testing

@testable import PortfolioTV

/// The needle moves on UIKit Dynamics' own clock, so these wait for it to settle, a second or two.
@MainActor
struct ScrubNeedleTests {
    typealias Needle = PlayerView.ScrubNeedle

    /// The system player's bar, on a 1920-point screen.
    let barWidth: CGFloat = 1760
    /// How far the needle's center travels from one end to the other.
    var track: CGFloat { barWidth - Needle.Metrics.needleWidth }

    /// A needle on the bar at `fraction`, with where playback is at `marker`.
    func needle(at fraction: Double, marker: Double = 0) -> Needle {
        let needle = Needle()
        needle.marker = marker
        needle.place(at: fraction, barWidth: barWidth)
        return needle
    }

    /// Waits until the needle has stood still for a fifth of a second, and gives where it is.
    @discardableResult
    func settled(_ needle: Needle) async -> Double {
        let deadline = ContinuousClock.now + .seconds(5)
        var last = needle.fraction, stillSince = ContinuousClock.now
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
            if needle.fraction != last {
                last = needle.fraction
                stillSince = .now
            } else if ContinuousClock.now - stillSince > .milliseconds(200) {
                break
            }
        }
        return last
    }

    /// How far a coast from the middle at `speed` carries the needle, in points.
    func coast(at speed: CGFloat) async -> CGFloat {
        let needle = needle(at: 0.5)
        needle.move(by: 0, speed: 0)
        needle.lifted(speed: speed)
        return CGFloat(await settled(needle) - 0.5) * track
    }

    @Test func gainsMoreTheFasterTheSwipe() {
        #expect(Needle.gain(atSpeed: 0) == 0.02)
        #expect(abs(Needle.gain(atSpeed: 500) - 0.0325) < 1e-12)
        #expect(Needle.gain(atSpeed: -500) == Needle.gain(atSpeed: 500))
        #expect(abs(Needle.gain(atSpeed: 1000) - 0.12) < 1e-12)
        #expect(Needle.gain(atSpeed: 5000) == 0.12)
    }

    @Test func movesBySwipesTranslationTimesItsGain() async {
        let needle = needle(at: 0.5)
        var reported = [Double]()
        needle.onMoved = { reported.append($0) }

        // The first move takes hold of the needle where it is.
        needle.move(by: 300, speed: 0)
        needle.move(by: 500, speed: 0)
        needle.move(by: 100, speed: 1000)

        let moved = CGFloat(await settled(needle) - 0.5) * track
        #expect(abs(moved - (500 * 0.02 + 100 * 0.12)) < 0.5)
        #expect(reported.last == needle.fraction)
    }

    @Test func coastsAfterAFastSwipeFurtherTheFasterAndStops() async throws {
        async let slower = coast(at: 4000)
        async let faster = coast(at: 8000)
        async let back = coast(at: -8000)
        let (four, eight, backward) = await (slower, faster, back)

        // Pushed to 3.6% of the finger's speed, it goes a fifth of a second's worth of that.
        #expect(abs(eight - 8000 * 0.036 / 5) < 3)
        #expect(abs(eight / four - 2) < 0.1)
        #expect(abs(backward + eight) < 1)
    }

    @Test func doesntCoastAfterASlowSwipe() async {
        #expect(abs(await coast(at: 900)) < 0.01)
    }

    @Test func aNewTouchStopsItCoasting() async throws {
        let needle = needle(at: 0.2)
        needle.move(by: 0, speed: 0)
        needle.lifted(speed: 8000)
        try await Task.sleep(for: .milliseconds(100))

        needle.touchBegan()
        let touchedAt = needle.fraction

        let after = (CGFloat(await settled(needle)) - CGFloat(touchedAt)) * track
        #expect(touchedAt > 0.2)
        #expect(after < 3)
    }

    @Test func catchesWherePlaybackIsAndStaysUntilTheSwipeMovesOn() async {
        let needle = needle(at: 0.5 + 20 / Double(track), marker: 0.5)
        needle.move(by: 0, speed: 0)

        // Slowly toward it from 20 points away, to 10: it catches there.
        needle.move(by: -500, speed: -100)
        #expect(await settled(needle) == 0.5)
        #expect(needle.isAtMarker)

        // It holds for 5 points of the swipe's travel, then goes on from there.
        needle.move(by: -100, speed: -100)
        #expect(await settled(needle) == 0.5)
        needle.move(by: -200, speed: -100)
        let moved = CGFloat(await settled(needle) - 0.5) * track
        #expect(abs(moved + 4) < 0.5)
    }

    @Test func passesWherePlaybackIsWhenFast() async {
        let needle = needle(at: 0.5 + 20 / Double(track), marker: 0.5)
        needle.move(by: 0, speed: 0)

        needle.move(by: -100, speed: -2000)

        let moved = CGFloat(await settled(needle) - 0.5) * track
        #expect(abs(moved - 8) < 0.5)
    }

    @Test func stopsAtTheBarsEnds() async {
        let needle = needle(at: 0.98)
        needle.move(by: 0, speed: 0)
        needle.lifted(speed: 30_000)
        #expect(await settled(needle) == 1)

        needle.touchBegan()
        needle.move(by: 0, speed: 0)
        needle.move(by: -100_000, speed: -1000)
        #expect(await settled(needle) == 0)
    }

    /// Waits until the needle stops interacting, and gives how long that took.
    func stoppedInteracting(_ needle: Needle) async throws -> Duration {
        let start = ContinuousClock.now
        while needle.isInteracting, ContinuousClock.now - start < .seconds(5) {
            try await Task.sleep(for: .milliseconds(20))
        }
        return ContinuousClock.now - start
    }

    @Test func interactsWhileAFingerMovesItAndUntilItsCoastHasSettled() async throws {
        let needle = needle(at: 0.5)
        var changes = [Bool]()
        needle.onInteractingChanged = { changes.append($0) }
        #expect(!needle.isInteracting)

        needle.move(by: 0, speed: 0)
        #expect(needle.isInteracting)
        needle.lifted(speed: 8000)
        try await Task.sleep(for: .milliseconds(300))
        #expect(needle.isInteracting)

        // Visibly still within about two thirds of a second, then at rest about a second after that.
        let settling = try await stoppedInteracting(needle)
        #expect(!needle.isInteracting)
        #expect(settling < .seconds(3))
        #expect(changes == [true, false])
    }

    @Test func letsGoOfAFingerThatRests() async throws {
        let needle = needle(at: 0.5)
        needle.move(by: 0, speed: 0)
        try await Task.sleep(for: Needle.Metrics.restingDelay - .milliseconds(200))
        #expect(needle.isInteracting)

        let resting = try await stoppedInteracting(needle)

        #expect(!needle.isInteracting)
        #expect(resting < .seconds(2))
    }
}
