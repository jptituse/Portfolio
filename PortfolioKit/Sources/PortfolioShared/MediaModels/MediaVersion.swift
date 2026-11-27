/// One of an item's versions, as the file it is: how it's stored, and the video, audio and subtitles in
/// it.
public struct MediaVersion: Hashable, Sendable {
    /// The file's format, such as "mkv".
    public let container: String?
    /// How big the file is, in bytes.
    public let size: Int64?
    /// Its bitrate as it is, in bits per second.
    public let bitrate: Int?
    public let video: Video?
    public let audio: [Audio]
    public let subtitles: [Subtitles]

    public init(container: String? = nil, size: Int64? = nil, bitrate: Int? = nil, video: Video? = nil, audio: [Audio] = [], subtitles: [Subtitles] = []) {
        self.container = container
        self.size = size
        self.bitrate = bitrate
        self.video = video
        self.audio = audio
        self.subtitles = subtitles
    }

    /// The picture.
    public struct Video: Hashable, Sendable {
        /// Such as "hevc".
        public let codec: String?
        /// The codec's profile, such as "Main 10".
        public let profile: String?
        public let width: Int?
        public let height: Int?
        /// Frames a second.
        public let frameRate: Double?
        public let bitDepth: Int?
        /// In bits per second.
        public let bitrate: Int?
        public let dynamicRange: DynamicRange

        public init(
            codec: String? = nil,
            profile: String? = nil,
            width: Int? = nil,
            height: Int? = nil,
            frameRate: Double? = nil,
            bitDepth: Int? = nil,
            bitrate: Int? = nil,
            dynamicRange: DynamicRange = .sdr
        ) {
            self.codec = codec
            self.profile = profile
            self.width = width
            self.height = height
            self.frameRate = frameRate
            self.bitDepth = bitDepth
            self.bitrate = bitrate
            self.dynamicRange = dynamicRange
        }
    }

    /// How bright and colorful the picture can be.
    public indirect enum DynamicRange: Hashable, Sendable {
        case sdr
        /// High dynamic range of a kind the server doesn't name.
        case hdr
        case hdr10
        case hdr10Plus
        case hlg
        /// Dolby Vision, with `profile` and `level` (such as 8 and 6), the signal its base layer is
        /// compatible with on its own (the second part of "8.1"), whether it has an enhancement layer,
        /// and what plays where Dolby Vision doesn't, if anything.
        case dolbyVision(profile: Int?, level: Int?, compatibility: Int?, hasEnhancementLayer: Bool, fallback: DynamicRange?)
    }

    /// An audio track.
    public struct Audio: Hashable, Sendable {
        /// What its server calls it, such as "English - Dolby TrueHD + Dolby Atmos - 7.1 - Default".
        public let title: String
        /// As a language code.
        public let language: String?
        /// Such as "truehd".
        public let codec: String?
        /// The codec's profile, such as "Dolby TrueHD + Dolby Atmos" or "DTS-HD MA".
        public let profile: String?
        public let channels: Int?
        /// Such as "7.1".
        public let channelLayout: String?
        public let spatialAudio: SpatialAudio?
        public let isDefault: Bool
        /// In bits per second.
        public let bitrate: Int?

        public init(
            title: String,
            language: String? = nil,
            codec: String? = nil,
            profile: String? = nil,
            channels: Int? = nil,
            channelLayout: String? = nil,
            spatialAudio: SpatialAudio? = nil,
            isDefault: Bool = false,
            bitrate: Int? = nil
        ) {
            self.title = title
            self.language = language
            self.codec = codec
            self.profile = profile
            self.channels = channels
            self.channelLayout = channelLayout
            self.spatialAudio = spatialAudio
            self.isDefault = isDefault
            self.bitrate = bitrate
        }
    }

    /// Audio placed around the listener, heights included.
    public enum SpatialAudio: Hashable, Sendable {
        case dolbyAtmos
        case dtsX
    }

    /// A subtitle track.
    public struct Subtitles: Hashable, Sendable {
        public let title: String
        /// As a language code.
        public let language: String?
        /// Such as "subrip" or "PGSSUB".
        public let codec: String?
        /// Shown even with subtitles off, such as for signs and foreign dialogue.
        public let isForced: Bool
        /// For the deaf and hard of hearing (SDH): sounds and speakers as well as dialogue.
        public let isForHearingImpaired: Bool
        /// Drawn as text, rather than as pictures, as a Blu-ray's or DVD's are.
        public let isText: Bool
        /// In a file of its own, beside the media.
        public let isExternal: Bool

        public init(
            title: String,
            language: String? = nil,
            codec: String? = nil,
            isForced: Bool = false,
            isForHearingImpaired: Bool = false,
            isText: Bool = true,
            isExternal: Bool = false
        ) {
            self.title = title
            self.language = language
            self.codec = codec
            self.isForced = isForced
            self.isForHearingImpaired = isForHearingImpaired
            self.isText = isText
            self.isExternal = isExternal
        }
    }
}
