import Foundation
import PortfolioShared
import Testing

@testable import PortfolioSharedUI

struct PlaybackDefaultsTests {
    let source = PlaybackSource(
        url: URL(string: "https://media.test/film.mkv")!,
        audioTracks: [
            MediaTrack(id: 1, title: "English", language: "eng", isDefault: true),
            MediaTrack(id: 2, title: "French - Commentary", language: "fre"),
            MediaTrack(id: 3, title: "French", language: "FRE", isDefault: true),
        ],
        subtitleTracks: [
            MediaTrack(id: 10, title: "English - Forced", language: "eng", isForced: true),
            MediaTrack(id: 11, title: "English", language: "eng"),
            MediaTrack(id: 12, title: "French", language: "fre"),
            MediaTrack(id: 13, title: "Spanish - PGSSUB", language: "spa", isText: false),
        ],
        audioTrack: 1
    )

    @Test func asksForNothingMoreThanTheServerWouldWithoutSettings() {
        let defaults = PlaybackDefaults()

        #expect(defaults.startingRequest == PlaybackRequest())
        #expect(defaults.audioTrack(in: source) == nil)
        #expect(defaults.subtitles(in: source) == nil)
        #expect(defaults.skipBack == ProfilePreferences.defaultSkip)
        #expect(defaults.skipForward == ProfilePreferences.defaultSkip)
    }

    @Test @MainActor func skipsAsSettingsSay() {
        let suite = UserDefaults(suiteName: "PlaybackDefaultsTests-\(UUID().uuidString)")!
        let preferences = ProfilePreferences(profile: ProfileID(serverID: "server-1", userID: "alex"), defaults: suite)
        preferences.skipBack = .seconds(10)
        preferences.skipForward = .seconds(60)

        let defaults = PlaybackDefaults(preferences, item: MediaItem(id: "arrival", name: "Arrival", kind: .movie))

        #expect(defaults.skipBack == .seconds(10))
        #expect(defaults.skipForward == .seconds(60))
    }

    @Test func picksTheTrackTheFileMarksAmongSeveralInALanguageWhateverItsCase() {
        #expect(PlaybackDefaults(audioLanguage: .language("fre")).audioTrack(in: source) == 3)
    }

    @Test func changesNothingAlreadyPlayingInTheLanguage() {
        #expect(PlaybackDefaults(audioLanguage: .language("eng")).audioTrack(in: source) == nil)
        #expect(PlaybackDefaults(audioLanguage: .original).audioTrack(in: source) == nil)
    }

    @Test func keepsForcedSubtitlesTheServerShows() {
        var forced = source
        forced.subtitleTrack = 10

        #expect(PlaybackDefaults(subtitleLanguage: "fre").subtitles(in: forced) == nil)
    }

    @Test func swapsSubtitlesTheServerShowsForTheLanguageChosen() {
        var english = source
        english.subtitleTrack = 11

        #expect(PlaybackDefaults(subtitleLanguage: "fre").subtitles(in: english) == .track(12))
        #expect(PlaybackDefaults(subtitleLanguage: "eng").subtitles(in: english) == nil)
        #expect(PlaybackDefaults(subtitleLanguage: "jpn").subtitles(in: english) == nil)
    }

    @Test func turnsOffPicturesUnlessTheyCanShow() {
        var pictures = source
        pictures.subtitleTrack = 13
        var defaults = PlaybackDefaults()
        defaults.showsOriginalSubtitles = false

        #expect(defaults.subtitles(in: pictures) == .off)
        defaults.showsOriginalSubtitles = true
        #expect(defaults.subtitles(in: pictures) == nil)
    }

    @Test func swapsOnlyForPicturesThatCanShow() {
        var english = source
        english.subtitleTrack = 11
        var defaults = PlaybackDefaults(subtitleLanguage: "spa")
        defaults.showsOriginalSubtitles = false

        // Spanish comes only as pictures: the English text stays.
        #expect(defaults.subtitles(in: english) == nil)
        defaults.showsOriginalSubtitles = true
        #expect(defaults.subtitles(in: english) == .track(13))
    }
}
