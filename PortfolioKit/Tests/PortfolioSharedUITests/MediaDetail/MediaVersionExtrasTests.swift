import Foundation
import PortfolioShared
import Testing

@testable import PortfolioSharedUI

struct MediaVersionExtrasTests {
    func version(width: Int = 1920, height: Int = 1080, range: MediaVersion.DynamicRange = .sdr, audio: [MediaVersion.Audio] = [], subtitles: [MediaVersion.Subtitles] = []) -> MediaVersion {
        MediaVersion(video: MediaVersion.Video(width: width, height: height, dynamicRange: range), audio: audio, subtitles: subtitles)
    }

    @Test func badgesThePicturesResolutionAndRange() {
        #expect(version(width: 3840, height: 2160, range: .hdr10).badges == ["4K", "HDR10"])
        #expect(version(width: 3840, height: 1600, range: .dolbyVision(profile: 5, level: nil, compatibility: 0, hasEnhancementLayer: false, fallback: nil)).badges == ["4K", "Dolby Vision"])
        #expect(version(range: .hdr10Plus).badges == ["HD", "HDR10+"])
        #expect(version(width: 720, height: 480).badges == [])
    }

    @Test func badgesTheMainAudiosSpatialFormatElseItsSurround() {
        let atmos = MediaVersion.Audio(title: "", spatialAudio: .dolbyAtmos, isDefault: true)
        let stereo = MediaVersion.Audio(title: "", channels: 2)
        let surround = MediaVersion.Audio(title: "", channels: 6, channelLayout: "5.1(side)")

        #expect(version(audio: [stereo, atmos]).badges == ["HD", "Dolby Atmos"])
        #expect(version(audio: [surround]).badges == ["HD", "5.1"])
        #expect(version(audio: [MediaVersion.Audio(title: "", spatialAudio: .dtsX)]).badges == ["HD", "DTS:X"])
        #expect(version(audio: [stereo]).badges == ["HD"])
    }

    @Test func badgesSubtitlesForTheDeafElseCaptions() {
        #expect(version(subtitles: [MediaVersion.Subtitles(title: "", isForHearingImpaired: true)]).badges == ["HD", "SDH"])
        #expect(version(subtitles: [MediaVersion.Subtitles(title: "")]).badges == ["HD", "CC"])
        // Forced subtitles alone aren't captions.
        #expect(version(subtitles: [MediaVersion.Subtitles(title: "", isForced: true)]).badges == ["HD"])
    }

    @Test func tagsEachAudioLanguageOnceByItsTwoLetters() {
        let tracks = ["jpn", "eng", "jpn", "und", nil, "fre", "ger", "fil"].map { MediaVersion.Audio(title: "Track", language: $0) }

        // French and German by their older codes, as Jellyfin can give them; Filipino has no two letters,
        // so its three.
        #expect(version(audio: tracks).audioLanguageTags == ["JA", "EN", "FR", "DE", "FIL"])
    }

    @Test func describesThePicture() {
        let video = MediaVersion.Video(codec: "hevc", profile: "Main 10", width: 3840, height: 2160, frameRate: 23.976, bitDepth: 10)
        #expect(video.description == "4K · 3840 × 2160 · HEVC Main 10 · 10-bit · 23.976 fps")
        #expect(MediaVersion.Video(codec: "h264", width: 1920, height: 1080, frameRate: 24).description == "HD · 1920 × 1080 · H.264 · 24 fps")
    }

    @Test func describesDolbyVisionInFull() {
        let profile7 = MediaVersion.DynamicRange.dolbyVision(profile: 7, level: 6, compatibility: 6, hasEnhancementLayer: true, fallback: .hdr10)
        #expect(profile7.description == "Dolby Vision Profile 7.6, Level 6, with enhancement layer, HDR10 compatible")
        #expect(MediaVersion.DynamicRange.dolbyVision(profile: nil, level: nil, compatibility: nil, hasEnhancementLayer: false, fallback: nil).description == "Dolby Vision")
        #expect(MediaVersion.DynamicRange.hlg.description == "HLG")
    }

    @Test func describesAudio() {
        let truehd = MediaVersion.Audio(title: "", codec: "truehd", channels: 8, channelLayout: "7.1", spatialAudio: .dolbyAtmos, bitrate: 4_500_000)
        #expect(truehd.description == "Dolby TrueHD · Dolby Atmos · 7.1 · 4.5 Mbps")
        #expect(MediaVersion.Audio(title: "", codec: "dts", profile: "DTS-HD MA", channels: 6).description == "DTS-HD MA · 5.1")
        #expect(MediaVersion.Audio(title: "", codec: "aac", channels: 2, bitrate: 192_000).description == "AAC · Stereo · 192 kbps")
    }
}
