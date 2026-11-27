import Foundation
import PortfolioShared

/// How a version's file reads on its card and page: badges by its metadata, and its file's details.
extension MediaVersion {
    /// The badges after a card's metadata, as the TV app shows them: the picture's resolution and
    /// dynamic range, the main audio's spatial format or surround channels, and subtitles for the deaf
    /// and hard of hearing (SDH), else captions (CC) where there are subtitles at all.
    var badges: [String] {
        var badges: [String] = []
        if let resolution = video?.resolutionName { badges.append(resolution) }
        if let range = video?.dynamicRange.name, video?.dynamicRange != .sdr { badges.append(range) }
        if let audio = mainAudio {
            switch audio.spatialAudio {
            case .dolbyAtmos: badges.append("Dolby Atmos")
            case .dtsX: badges.append("DTS:X")
            case nil: if let channels = audio.surroundName { badges.append(channels) }
            }
        }
        if subtitles.contains(where: \.isForHearingImpaired) {
            badges.append("SDH")
        } else if subtitles.contains(where: { !$0.isForced }) {
            badges.append("CC")
        }
        return badges
    }

    /// The audio that plays unless another is chosen: the track marked default, else the first.
    /// The languages its audio comes in, each once, as tags: "EN", "JA". A language's two letters where
    /// it has them, else its three; none for audio of no language in particular.
    var audioLanguageTags: [String] {
        var tags: [String] = []
        for track in audio {
            guard let code = track.language?.lowercased(), !["und", "mis", "mul", "zxx"].contains(code) else { continue }
            // Jellyfin gives some languages by their older codes, which `Locale` doesn't know: "fre".
            let known = Self.terminologyCodes[code] ?? code
            let tag = (Locale.LanguageCode(known).identifier(.alpha2) ?? code).uppercased()
            if !tags.contains(tag) { tags.append(tag) }
        }
        return tags
    }

    /// ISO 639-2's bibliographic codes, which Jellyfin can give, by the terminology codes `Locale` knows.
    private static let terminologyCodes = [
        "alb": "sqi", "arm": "hye", "baq": "eus", "bur": "mya", "chi": "zho", "cze": "ces", "dut": "nld",
        "fre": "fra", "geo": "kat", "ger": "deu", "gre": "ell", "ice": "isl", "mac": "mkd", "mao": "mri",
        "may": "msa", "per": "fas", "rum": "ron", "slo": "slk", "tib": "bod", "wel": "cym",
    ]

    var mainAudio: Audio? {
        audio.first(where: \.isDefault) ?? audio.first
    }

    /// "MKV".
    var containerName: String? {
        container.map { $0.uppercased() }
    }

    /// "54.24 GB".
    var sizeName: String? {
        size.map { $0.formatted(.byteCount(style: .file)) }
    }

    /// "66.5 Mbps".
    static func bitrateName(_ bitrate: Int?) -> String? {
        guard let bitrate, bitrate > 0 else { return nil }
        let megabits = Double(bitrate) / 1_000_000
        if megabits >= 1 {
            return "\(megabits.formatted(.number.precision(.fractionLength(0...1)))) Mbps"
        }
        return "\((Double(bitrate) / 1_000).formatted(.number.precision(.fractionLength(0)))) kbps"
    }
}

extension MediaVersion.Video {
    /// "4K" from about 3200 pixels across, "HD" from about 1200, as the TV app badges them; nothing
    /// below.
    var resolutionName: String? {
        let width = width ?? 0
        let height = height ?? 0
        if width >= 3200 || height >= 1800 { return "4K" }
        if width >= 1200 || height >= 700 { return "HD" }
        return nil
    }

    /// "4K · 3840 × 2160 · HEVC Main 10 · 10-bit · 23.976 fps".
    var description: String {
        var parts: [String] = []
        if let width, let height {
            parts.append([resolutionName, "\(width) × \(height)"].compactMap { $0 }.joined(separator: " · "))
        }
        if let codec = codec.map(Self.codecName) {
            parts.append([codec, profile].compactMap { $0 }.joined(separator: " "))
        }
        if let bitDepth { parts.append("\(bitDepth)-bit") }
        if let frameRate { parts.append("\(frameRate.formatted(.number.precision(.fractionLength(0...3)))) fps") }
        return parts.joined(separator: " · ")
    }

    /// How Jellyfin's codec names read: "hevc" is "HEVC".
    static func codecName(_ codec: String) -> String {
        switch codec.lowercased() {
        case "hevc", "h265": "HEVC"
        case "h264", "avc": "H.264"
        case "av1": "AV1"
        case "vp9": "VP9"
        case "vp8": "VP8"
        case "mpeg2video": "MPEG-2"
        case "mpeg4": "MPEG-4"
        case "vc1": "VC-1"
        default: codec.uppercased()
        }
    }
}

extension MediaVersion.DynamicRange {
    /// "Dolby Vision", "HDR10+", "HDR10", "HLG", "HDR" or "SDR".
    var name: String {
        switch self {
        case .sdr: "SDR"
        case .hdr: "HDR"
        case .hdr10: "HDR10"
        case .hdr10Plus: "HDR10+"
        case .hlg: "HLG"
        case .dolbyVision: "Dolby Vision"
        }
    }

    /// In full: "Dolby Vision Profile 8.1, Level 6, HDR10 compatible", or with Profile 7's enhancement
    /// layer, "Dolby Vision Profile 7.6, Level 6, with enhancement layer, HDR10 compatible".
    var description: String {
        guard case .dolbyVision(let profile, let level, let compatibility, let hasEnhancementLayer, let fallback) = self else {
            return name
        }
        var parts = [
            "Dolby Vision" + (profile.map { profile in " Profile \(profile)" + (compatibility.map { ".\($0)" } ?? "") } ?? ""),
        ]
        if let level { parts.append("Level \(level)") }
        if hasEnhancementLayer { parts.append("with enhancement layer") }
        if let fallback { parts.append("\(fallback.name) compatible") }
        return parts.joined(separator: ", ")
    }
}

extension MediaVersion.Audio {
    /// "7.1" from eight channels, "5.1" from six; nothing for fewer.
    var surroundName: String? {
        if let channelLayout, channelLayout.contains(".") { return channelLayout.components(separatedBy: CharacterSet(charactersIn: "(")).first }
        switch channels ?? 0 {
        case 8...: return "7.1"
        case 6...: return "5.1"
        default: return nil
        }
    }

    /// "Dolby TrueHD · Dolby Atmos · 7.1 · 4.5 Mbps".
    var description: String {
        var parts: [String] = []
        parts.append(formatName)
        if let spatialAudio { parts.append(spatialAudio == .dolbyAtmos ? "Dolby Atmos" : "DTS:X") }
        if let channels = surroundName ?? channels.map({ $0 == 2 ? "Stereo" : $0 == 1 ? "Mono" : "\($0) channels" }) {
            parts.append(channels)
        }
        if let bitrate = MediaVersion.bitrateName(bitrate) { parts.append(bitrate) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The codec's name, with its profile where that says more: "DTS-HD MA" for "dts".
    var formatName: String {
        if let profile, let codec, codec.lowercased() == "dts" { return profile }
        switch codec?.lowercased() {
        case "truehd": return "Dolby TrueHD"
        case "eac3": return "Dolby Digital+"
        case "ac3": return "Dolby Digital"
        case "dts": return "DTS"
        case "aac": return "AAC"
        case "flac": return "FLAC"
        case "alac": return "ALAC"
        case "opus": return "Opus"
        case "vorbis": return "Vorbis"
        case "mp3": return "MP3"
        case let codec? where codec.hasPrefix("pcm"): return "PCM"
        case let codec?: return codec.uppercased()
        case nil: return ""
        }
    }
}

/// A language's name, from its code: "eng" is "English".
func languageName(_ code: String?) -> String? {
    guard let code, !code.isEmpty, code != "und" else { return nil }
    return Locale.current.localizedString(forLanguageCode: code) ?? code
}
