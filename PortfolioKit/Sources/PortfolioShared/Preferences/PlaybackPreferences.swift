/// How this device plays: the picture and sound choices Settings makes for everyone on it, which a
/// playback engine reads as it opens each item.
public struct PlaybackPreferences: Hashable, Sendable {
    public var dolbyVisionFEL: DolbyVisionFEL
    /// The speakers to render object audio (Dolby TrueHD Atmos, DTS:X) for, keeping it lossless, or nil
    /// to play it as the lossy surround sound it otherwise becomes.
    public var objectAudioLayout: SpeakerLayout?
    /// Whether to upscale video below 1080p, such as DVDs and 720p.
    public var upscalesLowResolution: Bool
    /// Whether to raise the dialogue over the rest of the sound.
    public var enhancesDialogue: Bool
    /// Whether to mix surround sound down to two channels, for TV speakers and headphones.
    public var downmixesToStereo: Bool
    /// How much later than the picture to play the sound; negative plays it earlier, as a soundbar or
    /// receiver that lags needs.
    public var audioDelay: Duration

    public init(
        dolbyVisionFEL: DolbyVisionFEL = .off,
        objectAudioLayout: SpeakerLayout? = nil,
        upscalesLowResolution: Bool = false,
        enhancesDialogue: Bool = false,
        downmixesToStereo: Bool = false,
        audioDelay: Duration = .zero
    ) {
        self.dolbyVisionFEL = dolbyVisionFEL
        self.objectAudioLayout = objectAudioLayout
        self.upscalesLowResolution = upscalesLowResolution
        self.enhancesDialogue = enhancesDialogue
        self.downmixesToStereo = downmixesToStereo
        self.audioDelay = audioDelay
    }
}

/// How Dolby Vision Profile 7 with a full enhancement layer (FEL) plays.
public enum DolbyVisionFEL: String, Hashable, Sendable, Codable, CaseIterable {
    /// As single-layer Profile 8.1, without its enhancement layer.
    case off
    /// Both layers decoded and composed by the engine.
    case full
    /// The base layer decoded by the system's player and the enhancement layer composed onto it.
    case fullThroughAVPlayer
}

/// A room's speakers, for rendering object audio: the speakers around the room, the subwoofer, and the
/// speakers overhead.
public enum SpeakerLayout: String, Hashable, Sendable, Codable, CaseIterable {
    case l512 = "5.1.2"
    case l514 = "5.1.4"
    case l712 = "7.1.2"
    case l714 = "7.1.4"
    case l916 = "9.1.6"
}
