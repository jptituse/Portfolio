import AetherEngine
import PortfolioSharedPlaybackEngine
import Testing

@testable import PortfolioSharedAetherPlaybackEngine

struct AetherPlaybackEngineTests {
    @Test(arguments: [
        (PlaybackPhase.idle, PlaybackStatus.idle),
        (.loading, .loading),
        (.playing, .playing),
        (.paused, .paused),
        (.ended, .ended),
    ])
    func reportsTheEnginesPhase(_ phase: PlaybackPhase, as status: PlaybackStatus) {
        #expect(AetherPlaybackEngine.status(for: phase) == status)
    }

    @Test(arguments: [PlaybackPhase.seeking, .rebuffering, .stalled(reconnecting: true), .stalled(reconnecting: false)])
    func reportsWaitingForMediaAsBuffering(_ phase: PlaybackPhase) {
        #expect(AetherPlaybackEngine.status(for: phase) == .buffering)
    }

    @Test func passesOnWhyItFailed() {
        #expect(AetherPlaybackEngine.status(for: .error("Source unavailable")) == .failed("Source unavailable"))
    }
}
