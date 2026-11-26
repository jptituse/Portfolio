import Foundation
import PortfolioShared
import PortfolioSharedJellyfinClient

/// Each of Settings' menus, built from what it sets as it is now.
extension SettingsViewModel {
    public func menu(_ id: SettingsMenu.ID) -> SettingsMenu {
        switch id {
        case .root: root
        case .appearance: appearance
        case .hero: hero
        case .heroCollection: heroGrouping(.collections)
        case .heroPlaylist: heroGrouping(.playlists)
        case .topShelf: topShelf
        case .video: video
        case .dolbyVisionFEL: dolbyVisionFEL
        case .audio: audio
        case .objectAudio: objectAudio
        case .audioDelay: audioDelay
        case .playback: playback
        case .minimumQuality: streamingQuality(isMaximum: false)
        case .maximumQuality: streamingQuality(isMaximum: true)
        case .audioLanguage: audioLanguage
        case .subtitleLanguage: subtitleLanguage
        case .skipForward: skip(isForward: true)
        case .skipBack: skip(isForward: false)
        case .segment(let kind): segment(kind)
        case .credits: credits
        case .servers: servers
        case .server(let serverID): server(serverID)
        case .accounts: accounts
        case .profile(let id): profile(id)
        case .account(let id): account(id)
        case .picture(let id): picture(id)
        case .services: services
        case .about: about
        }
    }

    // MARK: The first menu

    private var root: SettingsMenu {
        SettingsMenu(id: .root, title: "Settings", tile: .symbol(Self.symbol(of: .root)), sections: [
            SettingsMenu.Section(id: "menus", rows: Self.topLevel.map { menu in
                submenu(menu, title: Self.title(of: menu), value: nil, description: Self.summary(of: menu))
            }),
        ])
    }

    /// The menus the first one lists.
    static let topLevel: [SettingsMenu.ID] = [.appearance, .video, .audio, .playback, .servers, .accounts, .services, .about]

    static func title(of menu: SettingsMenu.ID) -> String {
        switch menu {
        case .appearance: "Appearance"
        case .video: "Video"
        case .audio: "Audio"
        case .playback: "Playback"
        case .servers: "Servers"
        case .accounts: "Accounts & Profiles"
        case .services: "Services"
        case .about: "About"
        default: "Settings"
        }
    }

    static func symbol(of menu: SettingsMenu.ID) -> String {
        switch menu {
        case .appearance, .hero, .heroCollection, .heroPlaylist, .topShelf: "paintbrush"
        case .video, .dolbyVisionFEL: "tv"
        case .audio, .objectAudio, .audioDelay: "hifispeaker.2"
        case .playback, .minimumQuality, .maximumQuality, .audioLanguage, .subtitleLanguage, .skipForward, .skipBack, .segment, .credits:
            "play.rectangle"
        case .servers, .server: "server.rack"
        case .accounts, .profile, .account, .picture: "person.2"
        case .services: "puzzlepiece.extension"
        case .about: "info.circle"
        case .root: "gearshape"
        }
    }

    static func summary(of menu: SettingsMenu.ID) -> String? {
        switch menu {
        case .appearance: "How Portfolio opens, and what Home shows."
        case .video: "How Portfolio plays Dolby Vision and lower resolutions."
        case .audio: "How Portfolio plays sound, for your speakers and your room."
        case .playback: "Streaming quality, languages, and skipping, for this profile."
        case .servers: "The servers added to this Apple TV, and how fast they are."
        case .accounts: "The accounts signed in on this Apple TV."
        case .services: "Services you connect to Portfolio, such as Seerr, will appear here."
        case .about: "Portfolio, its playback engine, and your servers."
        default: nil
        }
    }

    // MARK: Appearance

    private var appearance: SettingsMenu {
        var rows = [
            setting(
                "profilePicker", "Profile Picker on Launch", isOn: devicePreferences.showsProfilePickerOnLaunch,
                description: "Opens on “Who’s watching?” each time Portfolio starts. Off, it opens the profile opened last."
            ) { [devicePreferences] in devicePreferences.showsProfilePickerOnLaunch = $0 },
        ]
        if let profilePreferences {
            rows.append(submenu(.hero, title: "Hero", value: Self.name(of: profilePreferences.hero),
                                description: "What the banner at the top of Home goes through, for this profile."))
        }
        rows.append(submenu(.topShelf, title: "Top Shelf", value: Self.name(of: devicePreferences.topShelf),
                            description: "What Portfolio shows above its icon on the Home Screen."))
        if let profilePreferences {
            rows.append(setting(
                "spoilers", "Spoiler Protection", isOn: profilePreferences.hidesSpoilers,
                description: "Blurs the stills of episodes this profile hasn’t watched, and hides what happens in them."
            ) { profilePreferences.hidesSpoilers = $0 })
        }
        return SettingsMenu(id: .appearance, title: "Appearance", tile: .symbol(Self.symbol(of: .appearance)),
                            summary: Self.summary(of: .appearance), sections: [SettingsMenu.Section(id: "appearance", rows: rows)])
    }

    private var hero: SettingsMenu {
        let chosen = profilePreferences?.hero
        let collection = if case .collection(_, let name) = chosen { name } else { String?.none }
        let playlist = if case .playlist(_, let name) = chosen { name } else { String?.none }
        return SettingsMenu(id: .hero, title: "Hero", tile: .symbol(Self.symbol(of: .hero)),
                            summary: "What the banner at the top of Home goes through.", sections: [
            SettingsMenu.Section(id: "hero", rows: [
                choice("recentlyAdded", "Recently Added", isChosen: chosen == .recentlyAdded,
                       description: "The newest items in your libraries.") { [profilePreferences] in profilePreferences?.hero = .recentlyAdded },
                submenu(.heroCollection, title: "A Collection", value: collection, description: "The items of one of your collections."),
                submenu(.heroPlaylist, title: "A Playlist", value: playlist, description: "The items of one of your playlists."),
            ]),
        ])
    }

    private func heroGrouping(_ kind: JellyfinServerClient.Grouping) -> SettingsMenu {
        let isCollections = kind == .collections
        let items = isCollections ? collections : playlists
        let rows: [SettingsMenu.Row] = items.map { items in
            items.isEmpty
                ? [info("none", isCollections ? "No Collections" : "No Playlists")]
                : items.map { item in
                    let hero: ProfilePreferences.Hero = isCollections
                        ? .collection(id: item.id, name: item.name) : .playlist(id: item.id, name: item.name)
                    return choice(item.id, item.name, isChosen: profilePreferences?.hero == hero) { [profilePreferences] in
                        profilePreferences?.hero = hero
                    }
                }
        } ?? [info("loading", "Loading…")]
        let id: SettingsMenu.ID = isCollections ? .heroCollection : .heroPlaylist
        return SettingsMenu(id: id, title: isCollections ? "Collections" : "Playlists", tile: .symbol(Self.symbol(of: id)),
                            summary: "Home’s banner goes through the items of the one you choose.",
                            sections: [SettingsMenu.Section(id: "items", rows: rows)])
    }

    private var topShelf: SettingsMenu {
        choices(.topShelf, title: "Top Shelf", summary: "What Portfolio shows above its icon on the Home Screen.",
                values: TopShelfContent.allCases, chosen: devicePreferences.topShelf, name: Self.name(of:)) { [devicePreferences] in
            devicePreferences.topShelf = $0
        }
    }

    // MARK: Video

    private var video: SettingsMenu {
        SettingsMenu(id: .video, title: "Video", tile: .symbol(Self.symbol(of: .video)), summary: Self.summary(of: .video), sections: [
            SettingsMenu.Section(id: "video", rows: [
                submenu(.dolbyVisionFEL, title: "Dolby Vision FEL", value: Self.name(of: devicePreferences.dolbyVisionFEL),
                        description: Self.felSummary),
                setting(
                    "upscale", "Upscale SD and 720p", isOn: devicePreferences.upscalesLowResolution,
                    description: "Sharpens video below 1080p, such as DVDs and 720p, as it’s scaled up to your TV."
                ) { [devicePreferences] in devicePreferences.upscalesLowResolution = $0 },
            ]),
        ])
    }

    private static let felSummary = "Dolby Vision Profile 7 with a full enhancement layer, as on many UHD Blu-rays, carries extra picture detail in a second layer. Playing it takes more of the Apple TV."

    private var dolbyVisionFEL: SettingsMenu {
        let descriptions: [DolbyVisionFEL: String] = [
            .off: "Plays the main layer as Dolby Vision Profile 8.1, without the enhancement layer.",
            .full: "Decodes both layers and combines them, for the full picture.",
            .fullThroughAVPlayer: "Decodes the main layer with the Apple TV’s own player and adds the enhancement layer to it. Experimental: tested only on a Mac.",
        ]
        return choices(.dolbyVisionFEL, title: "Dolby Vision FEL", summary: Self.felSummary, values: DolbyVisionFEL.allCases,
                       chosen: devicePreferences.dolbyVisionFEL, name: Self.name(of:), description: { descriptions[$0] }) { [devicePreferences] in
            devicePreferences.dolbyVisionFEL = $0
        }
    }

    // MARK: Audio

    private var audio: SettingsMenu {
        SettingsMenu(id: .audio, title: "Audio", tile: .symbol(Self.symbol(of: .audio)), summary: Self.summary(of: .audio), sections: [
            SettingsMenu.Section(id: "audio", rows: [
                submenu(.objectAudio, title: "Lossless Object Rendering", value: devicePreferences.objectAudioLayout?.rawValue ?? "Off",
                        description: Self.objectAudioSummary),
                setting(
                    "dialogue", "Enhance Dialogue", isOn: devicePreferences.enhancesDialogue,
                    description: "Raises voices over music and effects. Sound that would play as it is, such as Atmos, is decoded to do it."
                ) { [devicePreferences] in devicePreferences.enhancesDialogue = $0 },
                setting(
                    "stereo", "Downmix to Stereo", isOn: devicePreferences.downmixesToStereo,
                    description: "Mixes surround sound down to two channels, for TV speakers and headphones."
                ) { [devicePreferences] in devicePreferences.downmixesToStereo = $0 },
                submenu(.audioDelay, title: "Audio Delay", value: Self.name(ofDelay: devicePreferences.audioDelay),
                        description: Self.audioDelaySummary),
                setting(
                    "mutePreviews", "Mute Previews", isOn: devicePreferences.mutesPreviews,
                    description: "Plays trailers and previews without sound."
                ) { [devicePreferences] in devicePreferences.mutesPreviews = $0 },
            ]),
        ])
    }

    private static let objectAudioSummary = "Keeps the full Dolby TrueHD Atmos or DTS:X signal, and renders its sounds for your speakers, overhead ones included. Off, it plays as lossy Dolby Digital Plus 5.1."

    private var objectAudio: SettingsMenu {
        choices(.objectAudio, title: "Lossless Object Rendering", summary: Self.objectAudioSummary,
                values: [nil] + SpeakerLayout.allCases.map(Optional.some), chosen: devicePreferences.objectAudioLayout,
                name: { $0?.rawValue ?? "Off" },
                description: { layout in
                    layout.map { "Renders for \($0.rawValue) speakers: \(Self.speakers(in: $0))." } ?? "Plays it as lossy Dolby Digital Plus 5.1, without heights."
                }) { [devicePreferences] in devicePreferences.objectAudioLayout = $0 }
    }

    private static let audioDelaySummary = "Plays the sound earlier or later than the picture. If voices come after lips move, as with some soundbars and receivers, play the sound earlier."

    private var audioDelay: SettingsMenu {
        choices(.audioDelay, title: "Audio Delay", summary: Self.audioDelaySummary, values: Self.audioDelays,
                chosen: devicePreferences.audioDelay, name: Self.name(ofDelay:)) { [devicePreferences] in
            devicePreferences.audioDelay = $0
        }
    }

    static let audioDelays: [Duration] = stride(from: -300, through: 300, by: 50).map { Duration.milliseconds($0) }

    // MARK: Playback

    private var playback: SettingsMenu {
        guard let profilePreferences else {
            return SettingsMenu(id: .playback, title: "Playback", tile: .symbol(Self.symbol(of: .playback)), summary: Self.summary(of: .playback), sections: [])
        }
        var quality = [
            submenu(.minimumQuality, title: "Minimum Streaming Quality", value: Self.name(ofBitrate: profilePreferences.minimumStreamingBitrate, none: "None"),
                    description: "The least quality to stream at, however the connection is."),
        ]
        if profilePreferences.minimumStreamingBitrate != nil {
            quality.append(submenu(.maximumQuality, title: "Maximum Streaming Quality",
                                   value: Self.name(ofBitrate: profilePreferences.maximumStreamingBitrate, none: "Original"),
                                   description: "The most quality to stream at. Original plays files as they are."))
        }
        let languages = [
            submenu(.audioLanguage, title: "Default Audio Language", value: audioLanguageName,
                    description: "The language audio plays in, where a film or episode has it."),
            submenu(.subtitleLanguage, title: "Default Subtitle Language", value: subtitleLanguageName,
                    description: "The language subtitles show in, where a film or episode has them."),
        ]
        let controls = [
            submenu(.skipForward, title: "Skip Forward", value: Self.name(ofSkip: profilePreferences.skipForward),
                    description: "How far clicking Right on the remote skips ahead."),
            submenu(.skipBack, title: "Skip Back", value: Self.name(ofSkip: profilePreferences.skipBack),
                    description: "How far clicking Left on the remote skips back."),
        ]
        let buttons = MediaSegmentKind.allCases.map { kind in
            submenu(.segment(kind), title: Self.name(of: kind), value: Self.name(of: profilePreferences.skipping(kind)),
                    description: Self.segmentDescription(kind))
        } + [
            submenu(.credits, title: "Credits", value: Self.name(of: profilePreferences.credits), description: Self.creditsSummary),
        ]
        return SettingsMenu(id: .playback, title: "Playback", tile: .symbol(Self.symbol(of: .playback)), summary: Self.summary(of: .playback), sections: [
            SettingsMenu.Section(id: "quality", rows: quality),
            SettingsMenu.Section(id: "languages", rows: languages),
            SettingsMenu.Section(id: "controls", header: "Controls", rows: controls),
            SettingsMenu.Section(id: "buttons", header: "Skip Buttons", rows: buttons),
        ])
    }

    private func streamingQuality(isMaximum: Bool) -> SettingsMenu {
        let id: SettingsMenu.ID = isMaximum ? .maximumQuality : .minimumQuality
        let minimum = profilePreferences?.minimumStreamingBitrate
        let bitrates = PlaybackQuality.bitrates.filter { !isMaximum || $0 > (minimum ?? 0) }
        return choices(id, title: isMaximum ? "Maximum Streaming Quality" : "Minimum Streaming Quality",
                       summary: isMaximum ? "The most quality to stream at." : "The least quality to stream at, however the connection is.",
                       values: [nil] + bitrates.map(Optional.some),
                       chosen: isMaximum ? profilePreferences?.maximumStreamingBitrate : minimum,
                       name: { Self.name(ofBitrate: $0, none: isMaximum ? "Original" : "None") }) { [profilePreferences] bitrate in
            guard let profilePreferences else { return }
            if isMaximum {
                profilePreferences.maximumStreamingBitrate = bitrate
            } else {
                profilePreferences.minimumStreamingBitrate = bitrate
                // A maximum only goes with a minimum, and above it.
                if let maximum = profilePreferences.maximumStreamingBitrate, bitrate.map({ maximum <= $0 }) ?? true {
                    profilePreferences.maximumStreamingBitrate = nil
                }
            }
        }
    }

    /// The audio language set, else the account's own, else Original.
    private var audioLanguageName: String {
        switch profilePreferences?.audioLanguage {
        case .original: "Original"
        case .language(let code): languageName(code)
        case nil: accountLanguages?.audio.map(languageName) ?? "Original"
        }
    }

    /// The subtitle language set, else the account's own, else English.
    private var subtitleLanguageName: String {
        languageName(profilePreferences?.subtitleLanguage ?? accountLanguages?.subtitle ?? Self.defaultSubtitleLanguage)
    }

    static let defaultSubtitleLanguage = "eng"

    func languageName(_ code: String) -> String {
        languages?.first { $0.code == code }?.name ?? Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    private var audioLanguage: SettingsMenu {
        let chosen = profilePreferences?.audioLanguage ?? accountLanguages?.audio.map(AudioLanguage.language) ?? .original
        let rows = [choice("original", "Original", isChosen: chosen == .original,
                           description: "The language it was made in.") { [profilePreferences] in profilePreferences?.audioLanguage = .original }]
            + languageRows(chosen: { chosen == .language($0) }) { [profilePreferences] in profilePreferences?.audioLanguage = .language($0) }
        return SettingsMenu(id: .audioLanguage, title: "Default Audio Language", tile: .symbol(Self.symbol(of: .audioLanguage)),
                            summary: "Starts out as your Jellyfin account’s audio language, if it has one.",
                            sections: [SettingsMenu.Section(id: "languages", rows: rows)])
    }

    private var subtitleLanguage: SettingsMenu {
        let chosen = profilePreferences?.subtitleLanguage ?? accountLanguages?.subtitle ?? Self.defaultSubtitleLanguage
        let rows = languageRows(chosen: { $0 == chosen }) { [profilePreferences] in profilePreferences?.subtitleLanguage = $0 }
        return SettingsMenu(id: .subtitleLanguage, title: "Default Subtitle Language", tile: .symbol(Self.symbol(of: .subtitleLanguage)),
                            summary: "Starts out as your Jellyfin account’s subtitle language, else English.",
                            sections: [SettingsMenu.Section(id: "languages", rows: rows)])
    }

    private func languageRows(chosen: (String) -> Bool, choose: @escaping (String) -> Void) -> [SettingsMenu.Row] {
        guard let languages else { return [info("loading", "Loading…")] }
        return languages.map { language in
            choice(language.code, language.name, isChosen: chosen(language.code)) { choose(language.code) }
        }
    }

    static let skips: [Duration] = [5, 10, 15, 30, 60].map { Duration.seconds($0) }

    private func skip(isForward: Bool) -> SettingsMenu {
        choices(isForward ? .skipForward : .skipBack, title: isForward ? "Skip Forward" : "Skip Back",
                summary: isForward ? "How far clicking Right on the remote skips ahead." : "How far clicking Left on the remote skips back.",
                values: Self.skips, chosen: (isForward ? profilePreferences?.skipForward : profilePreferences?.skipBack) ?? ProfilePreferences.defaultSkip,
                name: Self.name(ofSkip:)) { [profilePreferences] in
            if isForward { profilePreferences?.skipForward = $0 } else { profilePreferences?.skipBack = $0 }
        }
    }

    private func segment(_ kind: MediaSegmentKind) -> SettingsMenu {
        let descriptions: [SegmentSkipping: String] = [
            .off: "It plays.",
            .button: "A button offers to skip it.",
            .automatic: "It’s skipped.",
        ]
        return choices(.segment(kind), title: Self.name(of: kind), summary: Self.segmentDescription(kind), values: SegmentSkipping.allCases,
                       chosen: profilePreferences?.skipping(kind) ?? .button, name: Self.name(of:), description: { descriptions[$0] }) { [profilePreferences] in
            profilePreferences?.setSkipping($0, for: kind)
        }
    }

    private static let creditsSummary = "What happens when an episode’s credits start."

    private var credits: SettingsMenu {
        let descriptions: [CreditsSkipping: String] = [
            .off: "They play.",
            .upNext: "A button counts down to the next episode, and plays it. Where a scene follows the credits, it offers to skip them instead.",
            .automatic: "The next episode plays. Where a scene follows the credits, they’re skipped instead.",
        ]
        return choices(.credits, title: "Credits", summary: Self.creditsSummary, values: CreditsSkipping.allCases,
                       chosen: profilePreferences?.credits ?? .upNext, name: Self.name(of:), description: { descriptions[$0] }) { [profilePreferences] in
            profilePreferences?.credits = $0
        }
    }

    private static func segmentDescription(_ kind: MediaSegmentKind) -> String {
        switch kind {
        case .intro: "What happens at an episode’s opening titles, when the server has marked them."
        case .recap: "What happens at a “previously on”, when the server has marked it."
        case .preview: "What happens at a preview of the next episode, when the server has marked it."
        case .commercial: "What happens at a commercial break, when the server has marked it."
        }
    }

    // MARK: Servers

    private var servers: SettingsMenu {
        let rows = sessionManager.servers.map { saved in
            submenu(.server(saved.id), row: saved.id, title: saved.server.name, value: Self.address(of: saved.server.url),
                    description: "Jellyfin \(saved.server.version).")
        }
        return SettingsMenu(id: .servers, title: "Servers", tile: .symbol(Self.symbol(of: .servers)), summary: Self.summary(of: .servers), sections: [
            SettingsMenu.Section(id: "servers", rows: rows),
            SettingsMenu.Section(id: "add", rows: [
                SettingsMenu.Row(id: "addServer", title: "Add Server", description: "Adds a server by its address, and signs in to it.") { [weak self] in
                    self?.add(.server)
                },
                SettingsMenu.Row(id: "removeAll", title: "Remove All Servers", description: "Signs everyone out and removes every server, so Portfolio starts over as if just installed.",
                                 kind: .destructive) { [weak self] in self?.confirmRemovingAll() },
            ]),
        ])
    }

    private func server(_ serverID: MediaServer.ID) -> SettingsMenu {
        guard let saved = sessionManager.servers.first(where: { $0.id == serverID }) else {
            return SettingsMenu(id: .server(serverID), title: "Server", tile: .symbol(Self.symbol(of: .servers)), sections: [])
        }
        let isMoving = movingServer == serverID
        let host = saved.server.url.host() ?? ""
        let port = Self.port(of: saved.server.url).map(String.init) ?? ""
        return SettingsMenu(id: .server(serverID), title: saved.server.name, tile: .image(iconURLs[serverID], placeholder: Self.symbol(of: .servers)),
                            summary: "Jellyfin \(saved.server.version)", sections: [
            SettingsMenu.Section(id: "server", rows: [
                info("name", "Name", value: saved.server.name),
                SettingsMenu.Row(id: "address", title: "Address", value: isMoving ? "Checking…" : host,
                                 description: Self.addressDescription, kind: .text) { [weak self] in
                    self?.edit("Address", message: Self.addressDescription, text: host) { host in
                        Task { await self?.moveServer(serverID, host: host) }
                    }
                },
                SettingsMenu.Row(id: "port", title: "Port", value: isMoving ? "Checking…" : port,
                                 description: Self.portDescription, kind: .text) { [weak self] in
                    self?.edit("Port", message: Self.portDescription, text: port) { port in
                        guard let port = Int(port) else { return }
                        Task { await self?.moveServer(serverID, host: nil, port: port) }
                    }
                },
                SettingsMenu.Row(id: "speedTest", title: "Speed Test", value: speedValue(serverID),
                                 description: speedReport(serverID)) { [weak self] in
                    Task { await self?.testSpeed(of: serverID) }
                },
                SettingsMenu.Row(id: "delete", title: "Remove Server", description: "Signs its accounts out and takes them off the profile picker.",
                                 kind: .destructive) { [weak self] in self?.confirmRemoving(serverID) },
            ]),
        ])
    }

    private static let addressDescription = "Where this Apple TV reaches the server, such as 192.168.1.10. Its accounts stay signed in."
    private static let portDescription = "Jellyfin listens on 8096 unless it was set up otherwise."

    private func speedValue(_ serverID: MediaServer.ID) -> String? {
        switch speedTests[serverID] {
        case .measuring: "Testing…"
        case .measured(let speed): speed.bitrate.map(Self.name(ofBitrate:)) ?? Self.name(of: speed.responseTime)
        case .failed: "Failed"
        case nil: nil
        }
    }

    private func speedReport(_ serverID: MediaServer.ID) -> String {
        switch speedTests[serverID] {
        case .measured(let speed):
            let answer = "The server answers in \(Self.name(of: speed.responseTime))."
            guard let bitrate = speed.bitrate else { return answer + " Sign in to it to measure how fast it sends." }
            return answer + " It sends at \(Self.name(ofBitrate: bitrate)), enough for \(Self.streamable(bitrate))."
        case .failed(let message): return message
        case .measuring: return "Measuring how quickly the server answers, and how fast it sends."
        case nil: return "Measures how quickly the server answers, and how fast it sends to this Apple TV."
        }
    }

    // MARK: Accounts & Profiles

    private var accounts: SettingsMenu {
        let everyone = sessionManager.servers.flatMap { saved in saved.users.map { (saved, $0) } }
        let profiles = everyone.map { saved, user in
            submenu(.profile(Self.profile(user, on: saved)), row: "profile/\(saved.id)/\(user.id)", title: user.name, value: saved.server.name,
                    description: "On the profile picker, from \(saved.server.name).")
        }
        let accounts = everyone.filter { saved, user in saved.isSignedIn(user.id) }.map { saved, user in
            submenu(.account(Self.profile(user, on: saved)), row: "account/\(saved.id)/\(user.id)", title: user.name, value: saved.server.name,
                    description: "Signed in to \(saved.server.name).")
        }
        return SettingsMenu(id: .accounts, title: "Accounts & Profiles", tile: .symbol(Self.symbol(of: .accounts)),
                            summary: Self.summary(of: .accounts), sections: [
            SettingsMenu.Section(id: "profiles", header: "Profiles", rows: profiles),
            SettingsMenu.Section(id: "accounts", header: "Accounts", rows: accounts),
            SettingsMenu.Section(id: "add", rows: [
                SettingsMenu.Row(id: "addAccount", title: "Add Account", description: "Signs in to a server added to this Apple TV, or a new one.") { [weak self] in
                    self?.add(.account)
                },
            ]),
        ])
    }

    /// A profile on the profile picker: its picture and name, and the account it's of.
    private func profile(_ profile: ProfileID) -> SettingsMenu {
        guard let (saved, user) = person(profile) else {
            return SettingsMenu(id: .profile(profile), title: "Profile", tile: .symbol(Self.symbol(of: .accounts)), sections: [])
        }
        // FIXME: Combine one person's accounts across servers into the profile, and delete it (#29).
        return SettingsMenu(id: .profile(profile), title: user.name, tile: picture(of: user, on: saved),
                            summary: "On the profile picker, from \(saved.server.name).", sections: [
            SettingsMenu.Section(id: "profile", rows: identityRows(profile, user, on: saved) + [
                info("accounts", "Accounts", value: "\(user.name) on \(saved.server.name)"),
            ]),
        ])
    }

    /// An account signed in on this Apple TV: its picture and name, and signing it out.
    private func account(_ profile: ProfileID) -> SettingsMenu {
        guard let (saved, user) = person(profile) else {
            return SettingsMenu(id: .account(profile), title: "Account", tile: .symbol(Self.symbol(of: .accounts)), sections: [])
        }
        return SettingsMenu(id: .account(profile), title: user.name, tile: picture(of: user, on: saved),
                            summary: "Signed in to \(saved.server.name).", sections: [
            SettingsMenu.Section(id: "account", rows: identityRows(profile, user, on: saved) + [
                info("server", "Server", value: saved.server.name),
                SettingsMenu.Row(id: "signOut", title: "Sign Out", description: "Signs out on this Apple TV. The profile stays on the profile picker, and signs in with its password next time.",
                                 kind: .destructive) { [weak self] in self?.confirmSigningOut(profile) },
            ]),
        ])
    }

    /// Someone's name and picture: changed on their server while they're signed in here, else only shown.
    private func identityRows(_ profile: ProfileID, _ user: User, on saved: MediaServer) -> [SettingsMenu.Row] {
        let isSaving = savingProfile == profile
        guard saved.isSignedIn(user.id) else {
            return [info("name", "Name", value: user.name)]
        }
        return [
            SettingsMenu.Row(id: "name", title: "Name", value: isSaving ? "Saving…" : user.name,
                             description: "Their name on \(saved.server.name), where every Jellyfin app shows it.", kind: .text) { [weak self] in
                self?.edit("Name", message: "Their name on \(saved.server.name).", text: user.name) { name in
                    Task { await self?.rename(profile, to: name) }
                }
            },
            submenu(.picture(profile), row: "picture", title: "Picture", value: isSaving ? "Saving…" : nil,
                    description: "Their picture on \(saved.server.name), where every Jellyfin app shows it."),
        ]
    }

    /// The pictures someone can choose, each shown beside the menu while it has focus.
    private func picture(_ profile: ProfileID) -> SettingsMenu {
        guard let (saved, user) = person(profile) else {
            return SettingsMenu(id: .picture(profile), title: "Picture", tile: .symbol(Self.symbol(of: .accounts)), sections: [])
        }
        var rows = ProfilePicture.all.map { picture in
            SettingsMenu.Row(id: picture.id, title: picture.name, tile: .profilePicture(picture), kind: .choice(isChosen: false)) { [weak self] in
                self?.back()
                Task { await self?.setPicture(picture, for: profile) }
            }
        }
        if user.primaryImageTag != nil {
            rows.append(SettingsMenu.Row(id: "remove", title: "Remove Picture", description: "Shows their initials instead.",
                                         tile: .symbol(Self.noPicture), kind: .destructive) { [weak self] in
                self?.back()
                Task { await self?.setPicture(nil, for: profile) }
            })
        }
        return SettingsMenu(id: .picture(profile), title: "Picture", tile: picture(of: user, on: saved),
                            summary: "Choose a picture for \(user.name) on \(saved.server.name).",
                            sections: [SettingsMenu.Section(id: "pictures", rows: rows)])
    }

    private func person(_ profile: ProfileID) -> (MediaServer, User)? {
        guard let saved = sessionManager.servers.first(where: { $0.id == profile.serverID }),
            let user = saved.users.first(where: { $0.id == profile.userID }) else {
            return nil
        }
        return (saved, user)
    }

    private func picture(of user: User, on saved: MediaServer) -> SettingsMenu.Tile {
        .image(client.pictureURL(for: user, on: saved.server), placeholder: Self.noPicture)
    }

    private static func profile(_ user: User, on saved: MediaServer) -> ProfileID {
        ProfileID(serverID: saved.id, userID: user.id)
    }

    /// Someone without a picture.
    static let noPicture = "person.crop.circle"

    // MARK: Services and About

    private var services: SettingsMenu {
        // FIXME: List services as they're supported, such as Seerr (#31).
        SettingsMenu(id: .services, title: "Services", tile: .symbol(Self.symbol(of: .services)), summary: Self.summary(of: .services), sections: [
            SettingsMenu.Section(id: "services", rows: [info("none", "No Services Yet")]),
        ])
    }

    private var about: SettingsMenu {
        SettingsMenu(id: .about, title: "About", tile: .symbol(Self.symbol(of: .about)), summary: Self.summary(of: .about), sections: [
            SettingsMenu.Section(id: "app", rows: [
                info("portfolio", "Portfolio", value: appVersion),
                info("engine", engine.name, value: engine.version),
            ]),
            SettingsMenu.Section(id: "servers", header: "Servers", rows: sessionManager.servers.map { saved in
                info(saved.id, saved.server.name, value: "Jellyfin \(saved.server.version)")
            }),
        ])
    }

    // MARK: Rows

    private func submenu(_ menu: SettingsMenu.ID, row: SettingsMenu.Row.ID? = nil, title: String, value: String?, description: String?) -> SettingsMenu.Row {
        let id = row ?? title
        return SettingsMenu.Row(id: id, title: title, value: value, description: description, kind: .submenu) { [weak self] in
            self?.open(menu)
        }
    }

    /// A setting that's on or off, turned the other way by selecting it.
    private func setting(_ id: String, _ title: String, isOn: Bool, description: String, set: @escaping (Bool) -> Void) -> SettingsMenu.Row {
        SettingsMenu.Row(id: id, title: title, value: isOn ? "On" : "Off", description: description, kind: .setting) { set(!isOn) }
    }

    /// One of a menu's choices: choosing it goes back.
    private func choice(_ id: String, _ title: String, isChosen: Bool, description: String? = nil, choose: @escaping () -> Void) -> SettingsMenu.Row {
        SettingsMenu.Row(id: id, title: title, description: description, kind: .choice(isChosen: isChosen)) { [weak self] in
            choose()
            self?.back()
        }
    }

    private func info(_ id: String, _ title: String, value: String? = nil) -> SettingsMenu.Row {
        SettingsMenu.Row(id: id, title: title, value: value, kind: .info)
    }

    /// A menu of choices of one value.
    private func choices<Value: Equatable>(
        _ id: SettingsMenu.ID,
        title: String,
        summary: String,
        values: [Value],
        chosen: Value,
        name: @escaping (Value) -> String,
        description: @escaping (Value) -> String? = { _ in nil },
        choose: @escaping (Value) -> Void
    ) -> SettingsMenu {
        SettingsMenu(id: id, title: title, tile: .symbol(Self.symbol(of: id)), summary: summary, sections: [
            SettingsMenu.Section(id: "choices", rows: values.map { value in
                choice(name(value), name(value), isChosen: value == chosen, description: description(value)) { choose(value) }
            }),
        ])
    }

    // MARK: Names

    static func name(of hero: ProfilePreferences.Hero) -> String {
        switch hero {
        case .recentlyAdded: "Recently Added"
        case .collection(_, let name), .playlist(_, let name): name
        }
    }

    static func name(of content: TopShelfContent) -> String {
        switch content {
        case .continueWatching: "Continue Watching"
        case .recentlyAdded: "Recently Added"
        }
    }

    static func name(of fel: DolbyVisionFEL) -> String {
        switch fel {
        case .off: "Off"
        case .full: "Full"
        case .fullThroughAVPlayer: "Full through AVPlayer"
        }
    }

    static func name(of kind: MediaSegmentKind) -> String {
        switch kind {
        case .intro: "Intro"
        case .recap: "Recap"
        case .preview: "Previews"
        case .commercial: "Commercials"
        }
    }

    static func name(of skipping: SegmentSkipping) -> String {
        switch skipping {
        case .off: "Off"
        case .button: "Manual"
        case .automatic: "Auto"
        }
    }

    static func name(of credits: CreditsSkipping) -> String {
        switch credits {
        case .off: "Off"
        case .upNext: "Up Next"
        case .automatic: "Auto"
        }
    }

    /// "None", "300 ms earlier" or "50 ms later".
    static func name(ofDelay delay: Duration) -> String {
        let milliseconds = Int(delay.components.seconds) * 1000 + Int(delay.components.attoseconds / 1_000_000_000_000_000)
        return milliseconds == 0 ? "None" : milliseconds < 0 ? "\(-milliseconds) ms earlier" : "\(milliseconds) ms later"
    }

    /// "30 seconds" or "1 minute".
    static func name(ofSkip skip: Duration) -> String {
        let seconds = Int(skip.components.seconds)
        return seconds == 60 ? "1 minute" : "\(seconds) seconds"
    }

    static func name(ofBitrate bitrate: Int?, none: String) -> String {
        bitrate.map(name(ofBitrate:)) ?? none
    }

    /// As the player's Quality menu names it, such as "8 Mbps".
    static func name(ofBitrate bitrate: Int) -> String {
        PlaybackQuality.maxBitrate(bitrate).name
    }

    /// "23 ms".
    static func name(of responseTime: Duration) -> String {
        let milliseconds = Double(responseTime.components.seconds) * 1000 + Double(responseTime.components.attoseconds) / 1e15
        return "\(Int(milliseconds.rounded())) ms"
    }

    /// Roughly the best a bitrate streams well: 4K from 40 Mbps, 1080p from 10, 720p from 4, and the
    /// biggest 4K files, remuxes of UHD Blu-rays, from 120.
    static func streamable(_ bitrate: Int) -> String {
        switch bitrate {
        case 120_000_000...: "4K remuxes"
        case 40_000_000...: "4K"
        case 10_000_000...: "1080p"
        case 4_000_000...: "720p"
        default: "lower resolutions"
        }
    }

    /// The speakers of a layout, in words.
    static func speakers(in layout: SpeakerLayout) -> String {
        let parts = layout.rawValue.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 3 else { return layout.rawValue }
        return "\(parts[0]) around the room, a subwoofer, and \(parts[2]) overhead"
    }

    /// "192.168.1.10:8096": a server's address without its scheme.
    static func address(of url: URL) -> String {
        let address = url.absoluteString
        guard let scheme = address.range(of: "://") else { return address }
        return String(address[scheme.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
