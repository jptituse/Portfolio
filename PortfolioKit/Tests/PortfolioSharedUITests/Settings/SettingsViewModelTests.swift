import Foundation
import PortfolioShared
import PortfolioSharedJellyfinClient
import PortfolioSharedTestSupport
import Testing

@testable import PortfolioSharedUI

/// Settings, with a profile signed in to a mock Jellyfin server.
@MainActor
struct SettingsViewModelTests {
    let client = JellyfinServerClient.mocked
    let sessionManager = SessionManager(store: MediaServerStore(storage: InMemorySecureStorage()), authority: JellyfinServerClient.mocked)
    let devicePreferences = DevicePreferences(defaults: .forTesting())
    /// The server signed in to, unless a test signs in to its own. Kept for the whole test: a mock
    /// server stops answering once it's gone.
    let mock = MockJellyfinServer()

    /// Settings for someone signed in to `server`, or to `mock`.
    func settings(on server: MockJellyfinServer? = nil) async throws -> SettingsViewModel {
        let server = try await client.validateServer(at: (server ?? mock).url)
        let session = try await client.signIn(to: server, username: "alex", password: "hunter2")
        try sessionManager.signIn(session)
        return SettingsViewModel(
            devicePreferences: devicePreferences,
            profilePreferences: ProfilePreferences(profile: ProfileID(serverID: server.id, userID: session.user.id), defaults: .forTesting()),
            sessionManager: sessionManager,
            client: client,
            engine: ("AetherEngine", "7.59.0"),
            appVersion: "1.0 (12)"
        )
    }

    /// Selects the row `id` of the menu showing.
    func select(_ id: String, in settings: SettingsViewModel) throws {
        let row = try #require(settings.menu(settings.current).row(id), "No row \(id) in \(settings.current)")
        let select = try #require(row.select, "\(id) can't be selected")
        select()
    }

    func row(_ id: String, in settings: SettingsViewModel) -> SettingsMenu.Row? {
        settings.menu(settings.current).row(id)
    }

    func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    // MARK: Moving between menus

    @Test func listsItsMenusFirst() async throws {
        let settings = try await settings()

        #expect(settings.menu(.root).rows.map(\.title) == [
            "Appearance", "Video", "Audio", "Playback", "Servers", "Accounts & Profiles", "Services", "About",
        ])
        #expect(settings.menu(.root).title == "Settings")
    }

    @Test func opensAMenuOnItsFirstRowAndGoesBack() async throws {
        let settings = try await settings()

        try select("Video", in: settings)

        #expect(settings.path == [.video])
        #expect(settings.canGoBack)
        #expect(settings.focusTarget(in: .video) == "Dolby Vision FEL")
        settings.back()
        #expect(settings.path.isEmpty)
    }

    @Test func loadsWhatAMenuListsAsItOpensHoweverItsOpened() async throws {
        let mock = MockJellyfinServer(items: [.init(name: "Pixar", type: "BoxSet")])
        let settings = try await settings(on: mock)

        // As a navigation stack opens it, setting the path.
        settings.path = [.appearance, .hero, .heroCollection]
        await waitUntil { settings.menu(.heroCollection).rows.first?.title == "Pixar" }

        #expect(settings.menu(.heroCollection).rows.map(\.title) == ["Pixar"])
    }

    @Test func describesTheRowWithFocusElseTheMenu() async throws {
        let settings = try await settings()

        #expect(settings.description(of: "upscale", in: .video)?.hasPrefix("Sharpens video below 1080p") == true)
        #expect(settings.description(of: nil, in: .video) == "How Portfolio plays Dolby Vision and lower resolutions.")
    }

    // MARK: Settings

    @Test func turnsASettingOnAndOffInPlace() async throws {
        let settings = try await settings()
        try select("Appearance", in: settings)
        #expect(row("profilePicker", in: settings)?.value == "On")

        try select("profilePicker", in: settings)

        #expect(!devicePreferences.showsProfilePickerOnLaunch)
        #expect(row("profilePicker", in: settings)?.value == "Off")
        #expect(settings.path == [.appearance])
    }

    @Test func aChoiceGoesBackWithItMadeAndIsCheckedNextTime() async throws {
        let settings = try await settings()
        try select("Video", in: settings)
        #expect(row("Dolby Vision FEL", in: settings)?.value == "Off")
        try select("Dolby Vision FEL", in: settings)
        #expect(settings.focusTarget(in: .dolbyVisionFEL) == "Off")

        try select("Full", in: settings)

        #expect(devicePreferences.dolbyVisionFEL == .full)
        #expect(settings.path == [.video])
        #expect(row("Dolby Vision FEL", in: settings)?.value == "Full")
        #expect(settings.focusTarget(in: .dolbyVisionFEL) == "Full")
    }

    @Test func rendersObjectAudioForTheSpeakersChosen() async throws {
        let settings = try await settings()
        try select("Audio", in: settings)
        try select("Lossless Object Rendering", in: settings)

        #expect(settings.menu(.objectAudio).rows.map(\.title) == ["Off", "5.1.2", "5.1.4", "7.1.2", "7.1.4", "9.1.6"])
        try select("7.1.4", in: settings)

        #expect(devicePreferences.objectAudioLayout == .l714)
        #expect(row("Lossless Object Rendering", in: settings)?.value == "7.1.4")
    }

    @Test func playsTheSoundEarlierOrLater() async throws {
        let settings = try await settings()

        #expect(settings.menu(.audioDelay).rows.first?.title == "300 ms earlier")
        #expect(settings.menu(.audioDelay).rows.last?.title == "300 ms later")
        settings.open(.audioDelay)
        try select("100 ms earlier", in: settings)

        #expect(devicePreferences.audioDelay == .milliseconds(-100))
    }

    @Test func offersAMaximumQualityOnlyWithAMinimum() async throws {
        let settings = try await settings()
        let preferences = try #require(settings.profilePreferences)
        #expect(settings.menu(.playback).row("Maximum Streaming Quality") == nil)

        preferences.minimumStreamingBitrate = 8_000_000
        let maximums = settings.menu(.maximumQuality).rows.map(\.title)

        #expect(settings.menu(.playback).row("Maximum Streaming Quality")?.value == "Original")
        #expect(maximums.first == "Original")
        #expect(maximums.last == "10 Mbps")
    }

    @Test func aMinimumAboveTheMaximumClearsIt() async throws {
        let settings = try await settings()
        let preferences = try #require(settings.profilePreferences)
        preferences.minimumStreamingBitrate = 4_000_000
        preferences.maximumStreamingBitrate = 10_000_000
        settings.open(.minimumQuality)

        try select("20 Mbps", in: settings)

        #expect(preferences.minimumStreamingBitrate == 20_000_000)
        #expect(preferences.maximumStreamingBitrate == nil)
    }

    @Test func startsOnTheAccountsLanguagesAndListsTheServersOnes() async throws {
        var account = MockJellyfinServer.Account(name: "alex", password: "hunter2")
        account.audioLanguage = "spa"
        let withPreferences = MockJellyfinServer(accounts: [account])
        let settings = try await settings(on: withPreferences)

        try select("Playback", in: settings)
        // Once the account's preferences and the server's languages have loaded.
        await waitUntil { settings.menu(.audioLanguage).rows.count == 4 && row("Default Audio Language", in: settings)?.value == "Spanish" }

        #expect(row("Default Audio Language", in: settings)?.value == "Spanish")
        // Without one of the account's own, subtitles are in English.
        #expect(row("Default Subtitle Language", in: settings)?.value == "English")
        try select("Default Audio Language", in: settings)
        #expect(settings.menu(.audioLanguage).rows.map(\.title) == ["Original", "English", "French", "Spanish"])
        #expect(settings.focusTarget(in: .audioLanguage) == "spa")
        try select("original", in: settings)
        #expect(settings.profilePreferences?.audioLanguage == .original)
    }

    @Test func choosesACollectionForHomesBanner() async throws {
        let mock = MockJellyfinServer(items: [.init(name: "Pixar", type: "BoxSet")])
        let settings = try await settings(on: mock)
        try select("Appearance", in: settings)
        try select("Hero", in: settings)
        try select("A Collection", in: settings)
        await waitUntil { settings.menu(.heroCollection).rows.first?.title == "Pixar" }

        try select(mock.items[0].id, in: settings)

        #expect(settings.profilePreferences?.hero == .collection(id: mock.items[0].id, name: "Pixar"))
        #expect(settings.path == [.appearance, .hero])
        #expect(row("A Collection", in: settings)?.value == "Pixar")
    }

    // MARK: Servers

    @Test func listsTheServersAndTestsTheirSpeed() async throws {
        let settings = try await settings()
        let serverID = try #require(sessionManager.servers.first?.id)
        try select("Servers", in: settings)
        #expect(row(serverID, in: settings)?.title == "Living Room")

        try select(serverID, in: settings)
        try select("speedTest", in: settings)
        await waitUntil { ![nil, "Testing…"].contains(row("speedTest", in: settings)?.value) }

        #expect(row("speedTest", in: settings)?.value?.hasSuffix("bps") == true)
        #expect(settings.description(of: "speedTest", in: settings.current)?.hasPrefix("The server answers in") == true)
    }

    @Test func movingAServerToAnotherServersAddressSaysSoAndChangesNothing() async throws {
        let other = MockJellyfinServer(name: "Office")
        let settings = try await settings()
        let saved = try #require(sessionManager.servers.first)
        settings.open(.server(saved.id))

        try select("address", in: settings)
        settings.textDraft = other.url.host() ?? ""
        settings.textEdit?.save()
        await waitUntil { settings.confirmation != nil }

        #expect(settings.confirmation?.title == "That's Another Server")
        #expect(sessionManager.servers.first?.server.url == saved.server.url)
    }

    @Test func removingAServerAsksFirst() async throws {
        let settings = try await settings()
        let saved = try #require(sessionManager.servers.first)
        settings.open(.server(saved.id))

        try select("delete", in: settings)
        let confirmation = try #require(settings.confirmation)
        #expect(sessionManager.servers.count == 1)
        confirmation.actions.first?.perform()
        // It goes back out of the server's menu first, so the menu on show never loses its rows.
        #expect(settings.path.isEmpty)
        await waitUntil { sessionManager.servers.isEmpty }

        #expect(sessionManager.servers.isEmpty)
        #expect(sessionManager.state == .choosingProfile)
    }

    // MARK: Accounts

    @Test func signingOutTheLastAccountOnAServerOffersToRemoveItToo() async throws {
        let settings = try await settings()
        let saved = try #require(sessionManager.servers.first)
        let user = try #require(saved.users.first)
        try select("Accounts & Profiles", in: settings)
        #expect(row("account/\(saved.id)/\(user.id)", in: settings)?.title == "alex")
        try select("account/\(saved.id)/\(user.id)", in: settings)

        try select("signOut", in: settings)

        let confirmation = try #require(settings.confirmation)
        #expect(confirmation.title == "Remove Living Room Too?")
        #expect(confirmation.actions.map(\.title) == ["Sign Out and Remove Server", "Sign Out Only"])
        confirmation.actions[1].perform()
        await waitUntil { sessionManager.state == .choosingProfile }
        #expect(sessionManager.servers.first?.isSignedIn(user.id) == false)
        #expect(sessionManager.servers.count == 1)
    }

    @Test func listsEveryProfileOnThePickerAndTheAccountsSignedIn() async throws {
        let settings = try await settings()
        let saved = try #require(sessionManager.servers.first)
        let alex = try #require(saved.users.first)
        sessionManager.updateListedUsers([alex, User(id: "sam", name: "Sam", serverID: saved.id, primaryImageTag: nil)], on: saved.id)

        let menu = settings.menu(.accounts)

        #expect(menu.sections.map(\.header) == ["Profiles", "Accounts", nil])
        #expect(menu.sections[0].rows.map(\.title) == ["alex", "Sam"])
        #expect(menu.sections[1].rows.map(\.title) == ["alex"])
        // Someone signed out can't be changed from here.
        let sam = settings.menu(.profile(ProfileID(serverID: saved.id, userID: "sam")))
        #expect(sam.row("name")?.select == nil)
        #expect(sam.row("picture") == nil)
        #expect(sam.row("accounts")?.value == "Sam on Living Room")
    }

    @Test func renamesAnAccountOnItsServer() async throws {
        let settings = try await settings()
        let saved = try #require(sessionManager.servers.first)
        let profile = ProfileID(serverID: saved.id, userID: try #require(saved.users.first).id)
        settings.open(.account(profile))

        try select("name", in: settings)
        #expect(settings.textDraft == "alex")
        settings.textDraft = "Alex Rivera"
        settings.textEdit?.save()
        await waitUntil { sessionManager.state.session?.user.name == "Alex Rivera" }

        // The profile picker and the sidebar show it.
        #expect(sessionManager.servers.first?.users.first?.name == "Alex Rivera")
        #expect(sessionManager.state.session?.user.name == "Alex Rivera")
        #expect(row("name", in: settings)?.value == "Alex Rivera")
        #expect(settings.menu(settings.current).title == "Alex Rivera")
    }

    @Test func givesAnAccountOneOfThePicturesToChoose() async throws {
        let settings = try await settings()
        let saved = try #require(sessionManager.servers.first)
        let profile = ProfileID(serverID: saved.id, userID: try #require(saved.users.first).id)
        settings.open(.account(profile))
        try select("picture", in: settings)
        #expect(settings.menu(.picture(profile)).rows.map(\.title) == ProfilePicture.all.map(\.name))
        #expect(settings.menu(.picture(profile)).rows.first?.tile == .profilePicture(ProfilePicture.all[0]))

        try select("popcorn", in: settings)
        await waitUntil { sessionManager.servers.first?.users.first?.primaryImageTag != nil }

        #expect(settings.path == [.account(profile)])
        let upload = try #require(mock.uploadedPictures.first)
        // A PNG, base64-encoded, as Jellyfin takes it.
        #expect(Data(base64Encoded: upload)?.starts(with: [0x89, 0x50, 0x4E, 0x47]) == true)
        #expect(sessionManager.state.session?.user.primaryImageTag != nil)
        // Now it has one, it can be removed.
        #expect(settings.menu(.picture(profile)).row("remove") != nil)
    }

    @Test func groupsTheSkipTimesUnderControls() async throws {
        let settings = try await settings()

        let controls = try #require(settings.menu(.playback).sections.first { $0.header == "Controls" })

        #expect(controls.rows.map(\.title) == ["Skip Forward", "Skip Back"])
    }

    @Test func addingAnAccountStartsOnTheServersAndEndsOnceItsSaved() async throws {
        let settings = try await settings()
        try select("Accounts & Profiles", in: settings)

        try select("addAccount", in: settings)

        let adding = try #require(settings.adding)
        guard case .servers = adding.first else {
            Issue.record("Adding an account didn't start on the servers")
            return
        }
        adding.onAdded()
        #expect(settings.adding == nil)
    }

    @Test func addingAServerStartsOnTheWelcomeScreen() async throws {
        let settings = try await settings()
        try select("Servers", in: settings)

        try select("addServer", in: settings)

        guard case .welcome = settings.adding?.first else {
            Issue.record("Adding a server didn't start on the welcome screen")
            return
        }
    }

    // MARK: About

    @Test func namesTheAppItsEngineAndEachServersVersion() async throws {
        let settings = try await settings()
        let about = settings.menu(.about)

        #expect(about.rows.map(\.title) == ["Portfolio", "AetherEngine", "Living Room"])
        #expect(about.rows.map(\.value) == ["1.0 (12)", "7.59.0", "Jellyfin 10.11.2"])
        // Nothing in it can be selected, so its rows take focus.
        #expect(!about.hasSelectableRows)
        #expect(settings.focusTarget(in: .about) == "portfolio")
    }
}
