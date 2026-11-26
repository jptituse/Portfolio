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
