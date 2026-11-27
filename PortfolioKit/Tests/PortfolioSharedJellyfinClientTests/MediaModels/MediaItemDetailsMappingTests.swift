import Foundation
import JellyfinAPI
import PortfolioShared
import Testing

@testable import PortfolioSharedJellyfinClient

struct MediaItemDetailsMappingTests {
    func details() throws -> MediaItemDetails {
        MediaItemDetails(try Fixture.decode(BaseItemDto.self, from: "movie-details"))
    }

    @Test func mapsWhereAndWhenAMovieIsFrom() throws {
        let details = try details()

        #expect(details.studios == ["FilmNation Entertainment", "Lava Bear Films"])
        #expect(details.countries == ["United States of America", "Canada"])
        #expect(details.tagline == "Why are they here?")
        #expect(details.criticRating == 94)
        #expect(details.releaseDate == Date(timeIntervalSince1970: 1_478_736_000))
    }

    @Test func mapsTheCastAndCrewInTheServersOrder() throws {
        let details = try details()

        #expect(details.credits == [
            Credit(personID: "p1", name: "Amy Adams", kind: .actor, role: "Louise Banks", imageTag: "i-amy"),
            Credit(personID: "p2", name: "Jeremy Renner", kind: .actor, role: "Ian Donnelly"),
            // An empty role is no role.
            Credit(personID: "p3", name: "Denis Villeneuve", kind: .director, imageTag: "i-denis"),
            Credit(personID: "p4", name: "Eric Heisserer", kind: .writer, role: "Screenplay"),
        ])
    }

    @Test func mapsTheFirstVersionsFile() throws {
        let version = try #require(try details().version)

        #expect(version.container == "mkv")
        #expect(version.size == 58_237_419_520)
        #expect(version.bitrate == 66_512_000)
        #expect(version.video == MediaVersion.Video(
            codec: "hevc",
            profile: "Main 10",
            width: 3840,
            height: 2160,
            frameRate: Double(Float(23.976)),
            bitDepth: 10,
            bitrate: 58_000_000,
            dynamicRange: .dolbyVision(profile: 7, level: 6, compatibility: 6, hasEnhancementLayer: true, fallback: .hdr10)
        ))
        #expect(version.audio.map(\.title) == ["English - Dolby TrueHD + Dolby Atmos - 7.1 - Default", "French - Dolby Digital - 5.1"])
        #expect(version.audio[0].spatialAudio == .dolbyAtmos)
        #expect(version.audio[0].channelLayout == "7.1")
        #expect(version.audio[1].spatialAudio == nil)
        #expect(version.subtitles == [
            MediaVersion.Subtitles(title: "English - SDH - PGSSUB", language: "eng", codec: "PGSSUB", isForHearingImpaired: true, isText: false),
            MediaVersion.Subtitles(title: "French - Forced - SUBRIP - External", language: "fre", codec: "subrip", isForced: true, isExternal: true),
        ])
    }

    @Test(arguments: [
        (VideoRangeType.sdr, MediaVersion.DynamicRange.sdr),
        (.hdr10, .hdr10),
        (.hdr10Plus, .hdr10Plus),
        (.hlg, .hlg),
        (.doviWithHDR10, .dolbyVision(profile: 8, level: nil, compatibility: 1, hasEnhancementLayer: false, fallback: .hdr10)),
        (.dovi, .dolbyVision(profile: 8, level: nil, compatibility: 1, hasEnhancementLayer: false, fallback: nil)),
    ])
    func namesEachDynamicRange(_ type: VideoRangeType, as range: MediaVersion.DynamicRange) {
        var stream = MediaStream()
        stream.videoRangeType = type
        if case .dolbyVision = range {
            stream.dvProfile = 8
            stream.dvBlSignalCompatibilityID = 1
        }

        #expect(MediaVersion.DynamicRange(stream) == range)
    }
}
