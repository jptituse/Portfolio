import AetherEngine
import Foundation
import PortfolioShared
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

    // MARK: Settings

    let source = PlaybackSource(url: URL(string: "https://example.com/film.mkv")!, httpHeaders: ["Authorization": "token"])

    @Test func playsAsTheyComeWithFELAndObjectAudioOff() {
        let options = AetherPlaybackEngine.options(for: source, PlaybackPreferences())

        #expect(options.httpHeaders == ["Authorization": "token"])
        #expect(!options.preferDualLayerDolbyVision)
        #expect(options.objectAudioRendering == .off)
        #expect(!options.upscalesLowResolutionVideo)
        #expect(options.audioShaping == AudioShaping())
        #expect(options.audioDelaySeconds == 0)
    }

    @Test(arguments: [(DolbyVisionFEL.full, DualLayerRoute.softwareHost), (.fullThroughAVPlayer, .avPlayerOutput)])
    func composesFELOnTheRouteChosen(_ fel: DolbyVisionFEL, _ route: DualLayerRoute) {
        let options = AetherPlaybackEngine.options(for: source, PlaybackPreferences(dolbyVisionFEL: fel))

        #expect(options.preferDualLayerDolbyVision)
        #expect(options.dualLayerRoute == route)
    }

    @Test(arguments: [
        (SpeakerLayout.l512, SpatialSpeakerLayout.l512), (.l514, .l514), (.l712, .l712), (.l714, .l714), (.l916, .l916),
    ])
    func rendersObjectAudioForTheSpeakersChosen(_ layout: SpeakerLayout, _ engineLayout: SpatialSpeakerLayout) {
        let options = AetherPlaybackEngine.options(for: source, PlaybackPreferences(objectAudioLayout: layout))

        #expect(options.objectAudioRendering == .render(engineLayout))
    }

    @Test func shapesTheSoundAndMovesItInTime() {
        let options = AetherPlaybackEngine.options(for: source, PlaybackPreferences(
            upscalesLowResolution: true,
            enhancesDialogue: true,
            downmixesToStereo: true,
            audioDelay: .milliseconds(-150)
        ))

        #expect(options.upscalesLowResolutionVideo)
        #expect(options.audioShaping == AudioShaping(maxChannels: 2, dialogueGainDB: 6))
        #expect(abs(options.audioDelaySeconds + 0.15) < 1e-9)
    }

    @Test func reducesLoudSoundsKeepingSettingsShaping() {
        let preferences = PlaybackPreferences(enhancesDialogue: true, downmixesToStereo: true)

        let options = AetherPlaybackEngine.options(for: source, preferences, reducesLoudSounds: true)

        #expect(options.audioShaping == AudioShaping(maxChannels: 2, dialogueGainDB: 6, compressor: .night))
        #expect(AetherPlaybackEngine.audioShaping(PlaybackPreferences(), reducesLoudSounds: false) == AudioShaping())
    }
}
