import Foundation
import Observation

/// Settings for everyone on this device, kept in `UserDefaults`: how the app opens, how it plays, and
/// what it shows outside a profile. What each affects reads it when it needs it, so a change applies
/// from then on, to a player from the next play.
///
/// Some are kept before what reads them is built: `mutesPreviews` for trailers and previews, and
/// `topShelf` for the Top Shelf extension.
@MainActor
@Observable
public final class DevicePreferences {
    /// Whether launch opens on the profile picker. Off, it opens the profile opened last, if it's still
    /// signed in.
    public var showsProfilePickerOnLaunch: Bool {
        didSet { defaults.setEncoded(showsProfilePickerOnLaunch, forKey: Key.showsProfilePickerOnLaunch) }
    }
    public var dolbyVisionFEL: DolbyVisionFEL {
        didSet { defaults.setEncoded(dolbyVisionFEL, forKey: Key.dolbyVisionFEL) }
    }
    public var objectAudioLayout: SpeakerLayout? {
        didSet { defaults.setEncoded(objectAudioLayout, forKey: Key.objectAudioLayout) }
    }
    public var upscalesLowResolution: Bool {
        didSet { defaults.setEncoded(upscalesLowResolution, forKey: Key.upscalesLowResolution) }
    }
    public var enhancesDialogue: Bool {
        didSet { defaults.setEncoded(enhancesDialogue, forKey: Key.enhancesDialogue) }
    }
    public var downmixesToStereo: Bool {
        didSet { defaults.setEncoded(downmixesToStereo, forKey: Key.downmixesToStereo) }
    }
    /// See `PlaybackPreferences.audioDelay`.
    public var audioDelay: Duration {
        didSet { defaults.setEncoded(audioDelay, forKey: Key.audioDelay) }
    }
    /// Whether trailers and previews play without sound.
    public var mutesPreviews: Bool {
        didSet { defaults.setEncoded(mutesPreviews, forKey: Key.mutesPreviews) }
    }
    /// What Portfolio shows above its icon on the Home Screen.
    public var topShelf: TopShelfContent {
        didSet { defaults.setEncoded(topShelf, forKey: Key.topShelf) }
    }

    /// Where they're kept, as are the profiles' own: UI tests give each launch a fresh store.
    @ObservationIgnored public let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let playback = PlaybackPreferences()
        showsProfilePickerOnLaunch = defaults.decoded(forKey: Key.showsProfilePickerOnLaunch, or: true)
        dolbyVisionFEL = defaults.decoded(forKey: Key.dolbyVisionFEL, or: playback.dolbyVisionFEL)
        objectAudioLayout = defaults.decoded(forKey: Key.objectAudioLayout, or: playback.objectAudioLayout)
        upscalesLowResolution = defaults.decoded(forKey: Key.upscalesLowResolution, or: playback.upscalesLowResolution)
        enhancesDialogue = defaults.decoded(forKey: Key.enhancesDialogue, or: playback.enhancesDialogue)
        downmixesToStereo = defaults.decoded(forKey: Key.downmixesToStereo, or: playback.downmixesToStereo)
        audioDelay = defaults.decoded(forKey: Key.audioDelay, or: playback.audioDelay)
        mutesPreviews = defaults.decoded(forKey: Key.mutesPreviews, or: false)
        topShelf = defaults.decoded(forKey: Key.topShelf, or: .continueWatching)
    }

    /// How to play, as these settings say now.
    public var playback: PlaybackPreferences {
        PlaybackPreferences(
            dolbyVisionFEL: dolbyVisionFEL,
            objectAudioLayout: objectAudioLayout,
            upscalesLowResolution: upscalesLowResolution,
            enhancesDialogue: enhancesDialogue,
            downmixesToStereo: downmixesToStereo,
            audioDelay: audioDelay
        )
    }

    private enum Key {
        static let showsProfilePickerOnLaunch = "device.showsProfilePickerOnLaunch"
        static let dolbyVisionFEL = "device.dolbyVisionFEL"
        static let objectAudioLayout = "device.objectAudioLayout"
        static let upscalesLowResolution = "device.upscalesLowResolution"
        static let enhancesDialogue = "device.enhancesDialogue"
        static let downmixesToStereo = "device.downmixesToStereo"
        static let audioDelay = "device.audioDelay"
        static let mutesPreviews = "device.mutesPreviews"
        static let topShelf = "device.topShelf"
    }
}

/// What the Top Shelf shows.
public enum TopShelfContent: String, Hashable, Sendable, Codable, CaseIterable {
    case continueWatching
    case recentlyAdded
}
