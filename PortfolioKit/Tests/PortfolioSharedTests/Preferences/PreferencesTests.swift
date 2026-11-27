import Foundation
import Testing

@testable import PortfolioShared

@MainActor
struct DevicePreferencesTests {
    let defaults = UserDefaults(suiteName: "DevicePreferencesTests-\(UUID().uuidString)")!

    @Test func startsAsTheyComeWithFELAndObjectAudioOff() {
        let preferences = DevicePreferences(defaults: defaults)

        #expect(preferences.showsProfilePickerOnLaunch)
        #expect(preferences.playback == PlaybackPreferences())
        #expect(preferences.playback.dolbyVisionFEL == .off)
        #expect(preferences.playback.objectAudioLayout == nil)
        #expect(!preferences.mutesPreviews)
        #expect(preferences.topShelf == .continueWatching)
    }

    @Test func remembersEachSettingAfterARelaunch() {
        let preferences = DevicePreferences(defaults: defaults)
        preferences.showsProfilePickerOnLaunch = false
        preferences.dolbyVisionFEL = .full
        preferences.objectAudioLayout = .l714
        preferences.upscalesLowResolution = true
        preferences.enhancesDialogue = true
        preferences.downmixesToStereo = true
        preferences.audioDelay = .milliseconds(-150)
        preferences.mutesPreviews = true
        preferences.topShelf = .recentlyAdded

        let relaunched = DevicePreferences(defaults: defaults)

        #expect(!relaunched.showsProfilePickerOnLaunch)
        #expect(relaunched.playback == PlaybackPreferences(
            dolbyVisionFEL: .full,
            objectAudioLayout: .l714,
            upscalesLowResolution: true,
            enhancesDialogue: true,
            downmixesToStereo: true,
            audioDelay: .milliseconds(-150)
        ))
        #expect(relaunched.mutesPreviews)
        #expect(relaunched.topShelf == .recentlyAdded)
    }

    @Test func remembersTurningObjectAudioOffAgain() {
        let preferences = DevicePreferences(defaults: defaults)
        preferences.objectAudioLayout = .l916
        preferences.objectAudioLayout = nil

        #expect(DevicePreferences(defaults: defaults).objectAudioLayout == nil)
    }

    @Test func startsAsTheyComeIfWhatWasSavedCannotBeRead() {
        defaults.set(Data("not json".utf8), forKey: "device.dolbyVisionFEL")
        // A choice a later version took out.
        defaults.set(Data("\"upNext\"".utf8), forKey: "device.topShelf")

        let preferences = DevicePreferences(defaults: defaults)

        #expect(preferences.dolbyVisionFEL == .off)
        #expect(preferences.topShelf == .continueWatching)
    }
}

@MainActor
struct ProfilePreferencesTests {
    let defaults = UserDefaults(suiteName: "ProfilePreferencesTests-\(UUID().uuidString)")!
    let alex = ProfileID(serverID: "server-1", userID: "alex")
    let sam = ProfileID(serverID: "server-1", userID: "sam")

    @Test func startsAsTheyCome() {
        let preferences = ProfilePreferences(profile: alex, defaults: defaults)

        #expect(preferences.hero == .recentlyAdded)
        #expect(preferences.minimumStreamingBitrate == nil)
        #expect(preferences.maximumStreamingBitrate == nil)
        #expect(preferences.audioLanguage == nil)
        #expect(preferences.subtitleLanguage == nil)
        #expect(preferences.skipForward == .seconds(30))
        #expect(preferences.skipBack == .seconds(30))
        #expect(MediaSegmentKind.allCases.allSatisfy { preferences.skipping($0) == .button })
        #expect(preferences.credits == .upNext)
        #expect(!preferences.hidesSpoilers)
    }

    func episode(_ id: String, of show: String) -> MediaItem {
        MediaItem(id: id, name: id, kind: .episode, episode: EpisodeInfo(seriesID: show))
    }

    @Test func keepsEachProfilesRatingsOfItsItems() {
        let preferences = ProfilePreferences(profile: alex, defaults: defaults)
        let arrival = MediaItem(id: "arrival", name: "Arrival", kind: .movie)
        #expect(preferences.rating(of: arrival) == nil)

        preferences.rate(arrival, stars: 4)

        #expect(ProfilePreferences(profile: alex, defaults: defaults).rating(of: arrival) == 4)
        #expect(ProfilePreferences(profile: sam, defaults: defaults).rating(of: arrival) == nil)
        // In halves, from half a star to 5.
        preferences.rate(arrival, stars: 3.5)
        #expect(ProfilePreferences(profile: alex, defaults: defaults).rating(of: arrival) == 3.5)
        // To the nearest half, up to 5.
        preferences.rate(arrival, stars: 2.3)
        #expect(preferences.rating(of: arrival) == 2.5)
        preferences.rate(arrival, stars: 9)
        #expect(preferences.rating(of: arrival) == 5)
        // No stars at all takes it back.
        preferences.rate(arrival, stars: 0)
        #expect(preferences.rating(of: arrival) == nil)
        preferences.rate(arrival, stars: 4)
        preferences.rate(arrival, stars: nil)
        #expect(ProfilePreferences(profile: alex, defaults: defaults).rating(of: arrival) == nil)
    }

    @Test func keepsHowEachMovieOfEachProfilePlayedLast() {
        let preferences = ProfilePreferences(profile: alex, defaults: defaults)
        let arrival = MediaItem(id: "arrival", name: "Arrival", kind: .movie)
        let dune = MediaItem(id: "dune", name: "Dune", kind: .movie)
        #expect(!preferences.showsOriginalSubtitles(for: arrival))

        preferences.setShowsOriginalSubtitles(true, for: arrival)

        #expect(ProfilePreferences(profile: alex, defaults: defaults).showsOriginalSubtitles(for: arrival))
        #expect(!preferences.showsOriginalSubtitles(for: dune))
        #expect(!ProfilePreferences(profile: sam, defaults: defaults).showsOriginalSubtitles(for: arrival))
        preferences.setShowsOriginalSubtitles(false, for: arrival)
        #expect(!preferences.showsOriginalSubtitles(for: arrival))
    }

    @Test func changingAnEpisodeChangesEveryEpisodeOfItsShow() {
        let preferences = ProfilePreferences(profile: alex, defaults: defaults)
        let pilot = episode("pilot", of: "severance")
        let second = episode("second", of: "severance")
        let other = episode("other", of: "andor")

        preferences.setShowsOriginalSubtitles(true, for: pilot)
        // The show's other episodes too, but not another show's.
        #expect(preferences.showsOriginalSubtitles(for: second))
        #expect(!preferences.showsOriginalSubtitles(for: other))

        preferences.setShowsOriginalSubtitles(false, for: second)
        #expect(!preferences.showsOriginalSubtitles(for: pilot))
    }

    @Test func remembersEachSettingAfterARelaunch() {
        let preferences = ProfilePreferences(profile: alex, defaults: defaults)
        preferences.hero = .collection(id: "pixar", name: "Pixar")
        preferences.minimumStreamingBitrate = 8_000_000
        preferences.maximumStreamingBitrate = 40_000_000
        preferences.audioLanguage = .original
        preferences.subtitleLanguage = "spa"
        preferences.skipForward = .seconds(10)
        preferences.skipBack = .seconds(5)
        preferences.setSkipping(.automatic, for: .intro)
        preferences.setSkipping(.off, for: .commercial)
        preferences.credits = .automatic
        preferences.hidesSpoilers = true

        let relaunched = ProfilePreferences(profile: alex, defaults: defaults)

        #expect(relaunched.hero == .collection(id: "pixar", name: "Pixar"))
        #expect(relaunched.minimumStreamingBitrate == 8_000_000)
        #expect(relaunched.maximumStreamingBitrate == 40_000_000)
        #expect(relaunched.audioLanguage == .original)
        #expect(relaunched.subtitleLanguage == "spa")
        #expect(relaunched.skipForward == .seconds(10))
        #expect(relaunched.skipBack == .seconds(5))
        #expect(relaunched.skipping(.intro) == .automatic)
        #expect(relaunched.skipping(.commercial) == .off)
        #expect(relaunched.skipping(.recap) == .button)
        #expect(relaunched.credits == .automatic)
        #expect(relaunched.hidesSpoilers)
    }

    @Test func keepsEachProfilesOwn() {
        ProfilePreferences(profile: alex, defaults: defaults).hero = .playlist(id: "date-night", name: "Date Night")
        ProfilePreferences(profile: alex, defaults: defaults).audioLanguage = .language("jpn")

        let samsOwn = ProfilePreferences(profile: sam, defaults: defaults)

        #expect(samsOwn.hero == .recentlyAdded)
        #expect(samsOwn.audioLanguage == nil)
        #expect(ProfilePreferences(profile: alex, defaults: defaults).audioLanguage == .language("jpn"))
    }
}
