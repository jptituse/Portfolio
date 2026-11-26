import Foundation
import Observation
import PortfolioShared
import PortfolioSharedJellyfinClient

/// Settings: a menu of menus, each built as it is now (`menu(_:)`), and where in them someone is. It
/// keeps the device's and the open profile's preferences, manages the servers and accounts on this
/// device, and loads what its menus list from the server, such as languages and collections, as they
/// open.
///
/// Opening a menu pushes it on `path`, and going back pops it; each platform draws the move. Focus
/// arriving in a menu goes to `focusTarget(in:)`: the row it opened from when going back, the choice
/// made in a menu of choices, else its first row.
@MainActor
@Observable
public final class SettingsViewModel {
    /// The menus opened on top of the first, in order: a navigation stack's path, which pops them as
    /// someone goes back. What a menu lists loads as it opens.
    public var path: [SettingsMenu.ID] = [] {
        didSet {
            if path.count > oldValue.count, let opened = path.last { prepare(opened) }
        }
    }
    /// A question to answer before something that can't be undone, such as removing a server.
    public var confirmation: SettingsConfirmation?
    /// Adding a server or an account, while that's under way.
    public var adding: ProfilesViewModel?
    /// A value being typed, such as a server's address, while it is.
    public var textEdit: SettingsTextEdit?
    /// What's typed so far.
    public var textDraft = ""

    /// The languages the server knows, once loaded.
    private(set) var languages: [Language]?
    /// The languages the account prefers on its server, once loaded.
    private(set) var accountLanguages: LanguagePreferences?
    private(set) var collections: [MediaItem]?
    private(set) var playlists: [MediaItem]?
    /// Each server's icon, once its web client has said where it is.
    private(set) var iconURLs: [MediaServer.ID: URL] = [:]
    private(set) var speedTests: [MediaServer.ID: SpeedTest] = [:]
    /// The server whose address is being checked, while it is.
    private(set) var movingServer: MediaServer.ID?
    /// The profile whose name or picture is being saved, while it is.
    private(set) var savingProfile: ProfileID?

    @ObservationIgnored let devicePreferences: DevicePreferences
    @ObservationIgnored let profilePreferences: ProfilePreferences?
    @ObservationIgnored let sessionManager: SessionManager
    @ObservationIgnored let client: JellyfinServerClient
    /// The playback engine's name and version, for About.
    @ObservationIgnored let engine: (name: String, version: String)
    /// The app's version and build, for About.
    @ObservationIgnored let appVersion: String

    init(
        devicePreferences: DevicePreferences,
        profilePreferences: ProfilePreferences?,
        sessionManager: SessionManager,
        client: JellyfinServerClient,
        engine: (name: String, version: String),
        appVersion: String = SettingsViewModel.bundleVersion()
    ) {
        self.devicePreferences = devicePreferences
        self.profilePreferences = profilePreferences
        self.sessionManager = sessionManager
        self.client = client
        self.engine = engine
        self.appVersion = appVersion
    }

    /// The menu on show: the last opened, or the first.
    public var current: SettingsMenu.ID { path.last ?? .root }

    public var canGoBack: Bool { !path.isEmpty }

    /// The open profile's session, for what's loaded from its server.
    var session: UserSession? { sessionManager.state.session }

    // MARK: Moving between menus

    /// Opens `menu` on top of the one on show.
    func open(_ menu: SettingsMenu.ID) {
        path.append(menu)
    }

    /// Back to the menu before.
    public func back() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    /// The row focus goes to as `menu` opens: the choice made, in a menu of choices, else its first row
    /// that can be selected. Going back, the navigation stack puts it back on the row that opened the
    /// menu left.
    public func focusTarget(in menu: SettingsMenu.ID) -> SettingsMenu.Row.ID? {
        let built = self.menu(menu)
        if let chosen = built.rows.first(where: { if case .choice(true) = $0.kind { true } else { false } }) {
            return chosen.id
        }
        return built.rows.first { $0.select != nil || !built.hasSelectableRows }?.id
    }

    /// What's shown beside `menu` while `row` has focus: its description, else the menu's summary.
    public func description(of row: SettingsMenu.Row.ID?, in menu: SettingsMenu.ID) -> String? {
        let built = self.menu(menu)
        return row.flatMap { built.row($0)?.description } ?? built.summary
    }

    /// Loads what a menu lists, if it hasn't been.
    private func prepare(_ menu: SettingsMenu.ID) {
        switch menu {
        case .playback, .audioLanguage, .subtitleLanguage:
            Task { await loadLanguages() }
        case .heroCollection:
            Task { await loadGroupings(.collections) }
        case .heroPlaylist:
            Task { await loadGroupings(.playlists) }
        case .servers, .server:
            Task { await loadIcons() }
        default:
            break
        }
    }

    // MARK: Loading

    private func loadLanguages() async {
        guard let session else { return }
        if accountLanguages == nil {
            accountLanguages = try? await client.languagePreferences(for: session)
        }
        if languages == nil {
            languages = try? await client.languages(for: session)
        }
    }

    private func loadGroupings(_ kind: JellyfinServerClient.Grouping) async {
        guard let session, let items = try? await client.groupings(kind, for: session) else { return }
        switch kind {
        case .collections: collections = items
        case .playlists: playlists = items
        }
    }

    private func loadIcons() async {
        for saved in sessionManager.servers where iconURLs[saved.id] == nil {
            if let iconURL = await client.iconURL(of: saved.server) {
                iconURLs[saved.id] = iconURL
            }
        }
    }

    // MARK: Servers

    /// Measures a server's speed, with one of its accounts signed in here, if any.
    func testSpeed(of serverID: MediaServer.ID) async {
        guard let saved = sessionManager.servers.first(where: { $0.id == serverID }), speedTests[serverID] != .measuring else { return }
        speedTests[serverID] = .measuring
        let session = saved.users.lazy.compactMap { saved.session(for: $0.id) }.first
        do {
            speedTests[serverID] = .measured(try await client.measureSpeed(of: saved.server, session: session))
        } catch {
            speedTests[serverID] = .failed(LoadingFailure.message(for: error, server: saved.server.name, activity: "testing its speed"))
        }
    }

    /// Starts typing a new value for something, from `text`. Saving it calls `save` with what was typed.
    func edit(_ title: String, message: String, text: String, save: @escaping (String) -> Void) {
        textDraft = text
        textEdit = SettingsTextEdit(title: title, message: message, save: { [weak self] in
            guard let self else { return }
            save(textDraft.trimmingCharacters(in: .whitespacesAndNewlines))
        })
    }

    /// Moves a server to a new host or port, once it's found to be the same server there. A different
    /// server, or none, leaves it where it was, and says why.
    func moveServer(_ serverID: MediaServer.ID, host: String? = nil, port: Int? = nil) async {
        guard movingServer == nil, let saved = sessionManager.servers.first(where: { $0.id == serverID }),
            var components = URLComponents(url: saved.server.url, resolvingAgainstBaseURL: false) else {
            return
        }
        if let host {
            guard !host.isEmpty else { return }
            components.host = host
        }
        if let port {
            components.port = port
        }
        guard let url = components.url, url != saved.server.url else { return }
        movingServer = serverID
        defer { movingServer = nil }
        do {
            let found = try await client.validateServer(at: url)
            guard found.id == serverID else {
                confirm(SettingsConfirmation(
                    title: "That's Another Server",
                    message: "\(found.name) is at that address, not \(saved.server.name). Its address hasn't changed."
                ))
                return
            }
            try sessionManager.updateAddress(of: found)
        } catch {
            confirm(SettingsConfirmation(
                title: "Couldn't Change the Address",
                message: LoadingFailure.message(for: error, server: saved.server.name, activity: "reaching it at that address")
            ))
        }
    }

    /// The port a URL reaches, given or its scheme's.
    static func port(of url: URL) -> Int? {
        url.port ?? (url.scheme == "https" ? 443 : url.scheme == "http" ? 80 : nil)
    }

    func confirmRemoving(_ serverID: MediaServer.ID) {
        guard let saved = sessionManager.servers.first(where: { $0.id == serverID }) else { return }
        confirm(SettingsConfirmation(
            title: "Remove \(saved.server.name)?",
            message: "Its accounts are signed out on this Apple TV and leave the profile picker.",
            actions: [.init(title: "Remove Server", isDestructive: true) { [weak self] in
                self?.remove(serverID)
            }]
        ))
    }

    /// Goes back out of the server's menus at once, then removes it once they've gone, so none on show
    /// loses its rows while focus is in it.
    private func remove(_ serverID: MediaServer.ID) {
        var wentBack = false
        while let last = path.last, Self.menu(last, isAbout: serverID) {
            back()
            wentBack = true
        }
        Task {
            if wentBack { try? await Task.sleep(for: Self.goingBack) }
            do {
                try await sessionManager.removeServer(serverID)
            } catch {
                confirm(SettingsConfirmation(title: "Couldn't Remove the Server", message: "It couldn't be removed from this Apple TV. Try again."))
            }
        }
    }

    func confirmRemovingAll() {
        confirm(SettingsConfirmation(
            title: "Remove All Servers?",
            message: "Everyone is signed out and every server is removed from this Apple TV, so the app starts over as if just installed.",
            actions: [.init(title: "Remove All Servers", isDestructive: true) { [weak self] in
                Task { try? await self?.sessionManager.removeAllServers() }
            }]
        ))
    }

    // MARK: Accounts

    /// Asks before signing an account out. Signing out a server's last signed-in account offers to
    /// remove the server too.
    func confirmSigningOut(_ profile: ProfileID) {
        guard let saved = sessionManager.servers.first(where: { $0.id == profile.serverID }),
            let user = saved.users.first(where: { $0.id == profile.userID }) else {
            return
        }
        let isLast = saved.users.allSatisfy { $0.id == user.id || !saved.isSignedIn($0.id) }
        let signOut = SettingsConfirmation.Action(title: isLast ? "Sign Out Only" : "Sign Out", isDestructive: !isLast) { [weak self] in
            self?.signOut(profile)
        }
        if isLast {
            confirm(SettingsConfirmation(
                title: "Remove \(saved.server.name) Too?",
                message: "\(user.name) is the last account signed in to \(saved.server.name) on this Apple TV. Removing the server takes its accounts off the profile picker.",
                actions: [
                    .init(title: "Sign Out and Remove Server", isDestructive: true) { [weak self] in
                        self?.remove(saved.id)
                    },
                    signOut,
                ]
            ))
        } else {
            confirm(SettingsConfirmation(
                title: "Sign Out \(user.name)?",
                message: "\(user.name) stays on the profile picker, and signs in with their password next time.",
                actions: [signOut]
            ))
        }
    }

    /// How long going back takes, for what waits until a menu has gone.
    static let goingBack = Duration.milliseconds(600)

    /// Goes back out of the account's menu at once, then signs it out.
    private func signOut(_ profile: ProfileID) {
        if path.last == .account(profile) { back() }
        Task { await sessionManager.signOut(profile.userID, on: profile.serverID) }
    }

    /// Whether a menu shows one of a server's settings, accounts or profiles.
    static func menu(_ menu: SettingsMenu.ID, isAbout serverID: MediaServer.ID) -> Bool {
        switch menu {
        case .server(let id): id == serverID
        case .profile(let profile), .account(let profile), .picture(let profile): profile.serverID == serverID
        default: false
        }
    }

    // MARK: Names and pictures

    /// Renames someone on their server, and takes them as it has them now.
    func rename(_ profile: ProfileID, to name: String) async {
        guard !name.isEmpty else { return }
        await save(profile) { [client] session in try await client.rename(session, to: name) }
    }

    /// Gives someone one of the pictures to choose, or none, on their server.
    func setPicture(_ picture: ProfilePicture?, for profile: ProfileID) async {
        guard let picture else {
            await save(profile) { [client] session in try await client.removePicture(for: session) }
            return
        }
        guard let png = picture.pngData() else { return }
        await save(profile) { [client] session in try await client.setPicture(png, for: session) }
    }

    /// Changes someone on their server with `change`, which answers with them as the server has them
    /// now, for the profile picker and the sidebar to show. A server that doesn't allow it says why.
    private func save(_ profile: ProfileID, _ change: @escaping (UserSession) async throws -> User) async {
        guard savingProfile == nil,
            let saved = sessionManager.servers.first(where: { $0.id == profile.serverID }),
            let session = saved.session(for: profile.userID) else {
            return
        }
        savingProfile = profile
        defer { savingProfile = nil }
        do {
            sessionManager.updateUser(try await change(session), on: saved.id)
        } catch JellyfinError.unauthorized {
            confirm(SettingsConfirmation(
                title: "Couldn't Save the Change",
                message: "\(saved.server.name) didn't let \(session.user.name) change it. An administrator may have turned that off for the account."
            ))
        } catch {
            confirm(SettingsConfirmation(
                title: "Couldn't Save the Change",
                message: LoadingFailure.message(for: error, server: saved.server.name, activity: "saving the change")
            ))
        }
    }

    // MARK: Adding

    /// Starts adding a server or an account, which ends once it's saved, or when it's dismissed.
    func add(_ addition: ProfilesViewModel.Addition) {
        let flow = ProfilesViewModel.adding(addition, client: client, sessionManager: sessionManager)
        flow.onAdded = { [weak self] in self?.adding = nil }
        adding = flow
    }

    private func confirm(_ confirmation: SettingsConfirmation) {
        self.confirmation = confirmation
    }

    /// "1.0 (12)": the app's version and build.
    nonisolated static func bundleVersion(_ bundle: Bundle = .main) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}

extension SettingsViewModel {
    /// Where measuring a server's speed has got to.
    enum SpeedTest: Equatable {
        case measuring
        case measured(ServerSpeed)
        case failed(String)
    }
}

/// A question Settings asks before something that can't be undone, with what each answer does. There's
/// always a way to cancel too.
public struct SettingsConfirmation: Identifiable {
    public let id = UUID()
    public let title: String
    public let message: String
    public let actions: [Action]

    init(title: String, message: String, actions: [Action] = []) {
        self.title = title
        self.message = message
        self.actions = actions
    }

    public struct Action: Identifiable {
        public let id = UUID()
        public let title: String
        public let isDestructive: Bool
        public let perform: () -> Void

        init(title: String, isDestructive: Bool = false, perform: @escaping () -> Void) {
            self.title = title
            self.isDestructive = isDestructive
            self.perform = perform
        }
    }
}

/// A value Settings asks for as text, such as a server's address.
public struct SettingsTextEdit: Identifiable {
    public let id = UUID()
    public let title: String
    public let message: String
    /// Saves what was typed.
    public let save: () -> Void
}
