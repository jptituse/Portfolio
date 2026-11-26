import Observation

/// Owns the servers added on this device and who's signed in to them: loads them at launch, opens a
/// profile, saves a new sign-in, signs accounts out, changes a server's address, and removes servers. `RootView` observes `state`, and the profile picker
/// observes `servers` and starts on `lastOpenedProfile`.
@MainActor
@Observable
public final class SessionManager {
    public private(set) var state: SessionState = .restoring
    /// The servers added on this device, in the order they were added.
    public private(set) var servers: [MediaServer] = []
    /// The profile opened last, on this launch or an earlier one, for the profile picker to start on.
    public private(set) var lastOpenedProfile: ProfileID?

    private let store: MediaServerStore
    private let authority: any SessionAuthority

    public init(store: MediaServerStore, authority: any SessionAuthority) {
        self.store = store
        self.authority = authority
    }

    /// Loads the saved servers at launch. No profile is open until one is picked. Servers that can't
    /// be read leave none, so the app starts as if freshly installed.
    public func restore() {
        load()
        state = .choosingProfile
    }

    /// Loads the saved servers at launch, then opens the profile opened last, as `open(_:on:)` does,
    /// while it's still signed in. Otherwise, or if the server no longer accepts its session, someone
    /// picks a profile. It's still restoring meanwhile.
    public func restoreOpeningLastProfile() async {
        load()
        if let last = lastOpenedProfile, await open(last.userID, on: last.serverID) { return }
        state = .choosingProfile
    }

    private func load() {
        servers = (try? store.load()) ?? []
        lastOpenedProfile = try? store.loadLastOpenedProfile()
    }

    /// Opens a saved profile, checking its session with the server first.
    ///
    /// - A session the server accepts signs in, with the user as the server knows them now.
    /// - If the server can't be reached, the saved session signs in anyway: being offline shouldn't
    ///   sign anyone out.
    /// - A session the server rejected is forgotten.
    ///
    /// - Returns: false if the user has to sign in again: they have no session, or it was rejected.
    public func open(_ userID: User.ID, on serverID: MediaServer.ID) async -> Bool {
        guard let saved = servers.first(where: { $0.id == serverID }),
            let session = saved.session(for: userID) else {
            return false
        }
        switch await authority.check(session) {
        case .valid(let user):
            update(serverID) { $0.remember(user) }
            opened(UserSession(server: session.server, user: user, accessToken: session.accessToken))
            return true
        case .unavailable:
            opened(session)
            return true
        case .revoked:
            update(serverID) { $0.accessTokens[userID] = nil }
            return false
        }
    }

    /// Saves a session that onboarding just created, adding its server if it's new, and signs in.
    ///
    /// - Throws: the storage error if the session couldn't be saved. Nothing changes then, because a
    ///   session that isn't saved would be lost at the next launch.
    public func signIn(_ session: UserSession) throws {
        try add(session)
        opened(session)
    }

    /// Saves a session that onboarding just created, adding its server if it's new, without opening it:
    /// an account added from Settings joins the profile picker, and the open profile stays open.
    ///
    /// - Throws: as `signIn(_:)`.
    public func add(_ session: UserSession) throws {
        var servers = servers
        if let index = servers.firstIndex(where: { $0.id == session.server.id }) {
            // The server may have been reached at a new address.
            servers[index].server = session.server
            servers[index].remember(session.user)
            servers[index].accessTokens[session.user.id] = session.accessToken
        } else {
            servers.append(
                MediaServer(server: session.server, users: [session.user], accessTokens: [session.user.id: session.accessToken])
            )
        }
        try store.save(servers)
        self.servers = servers
    }

    /// Makes `session` the open profile, and remembers it as the one opened last. Remembering is best
    /// effort: without it, the profile picker just starts on its first profile.
    private func opened(_ session: UserSession) {
        let profile = ProfileID(serverID: session.server.id, userID: session.user.id)
        lastOpenedProfile = profile
        try? store.saveLastOpenedProfile(profile)
        state = .signedIn(session)
    }

    /// Takes a user as their server knows them now, such as after they were renamed or given a new
    /// picture, here and in the open profile if it's theirs.
    public func updateUser(_ user: User, on serverID: MediaServer.ID) {
        update(serverID) { $0.remember(user) }
        if let session = state.session, session.server.id == serverID, session.user.id == user.id {
            state = .signedIn(UserSession(server: session.server, user: user, accessToken: session.accessToken))
        }
    }

    /// Takes the users a saved server lists now, keeping anyone else this device knows.
    public func updateListedUsers(_ users: [User], on serverID: MediaServer.ID) {
        update(serverID) { $0.update(listedUsers: users) }
    }

    /// Closes the open profile so someone can pick another. It stays signed in on this device, so it
    /// opens again straight from the profile picker.
    public func closeProfile() {
        guard state.session != nil else { return }
        state = .choosingProfile
    }

    /// Ends the current session on the server, then forgets its token. The user stays in the profile
    /// picker, signed out.
    ///
    /// Telling the server is best effort: signing out works offline too, and the server-side session
    /// can then be revoked from its dashboard.
    public func signOut() async {
        if let session = state.session {
            await signOut(session.user.id, on: session.server.id)
        }
        state = .choosingProfile
    }

    /// Ends a signed-in account's session on its server, then forgets its token, as `signOut()` does
    /// for the open profile. It stays on the profile picker, signed out. Signing out the open profile
    /// closes it.
    public func signOut(_ userID: User.ID, on serverID: MediaServer.ID) async {
        guard let session = servers.first(where: { $0.id == serverID })?.session(for: userID) else { return }
        let wasOpen = state.session.map { $0.user.id == userID && $0.server.id == serverID } ?? false
        update(serverID) { $0.accessTokens[userID] = nil }
        if wasOpen { state = .choosingProfile }
        try? await authority.endSession(session)
    }

    /// Forgets a server added on this device, with its profiles, as `removeAllServers()` does for every
    /// one: the open profile closes if it's on it, and with no servers left the app starts over as if
    /// freshly installed. Each of its signed-in sessions is then ended, best effort.
    ///
    /// - Throws: the storage error if it couldn't be removed. Nothing changes then.
    public func removeServer(_ serverID: MediaServer.ID) async throws {
        guard let removed = servers.first(where: { $0.id == serverID }) else { return }
        let remaining = servers.filter { $0.id != serverID }
        if remaining.isEmpty {
            try store.removeAll()
        } else {
            try store.save(remaining)
        }
        servers = remaining
        if lastOpenedProfile?.serverID == serverID {
            lastOpenedProfile = nil
            try? store.removeLastOpenedProfile()
        }
        if state.session?.server.id == serverID { state = .choosingProfile }
        for session in removed.users.compactMap({ removed.session(for: $0.id) }) {
            try? await authority.endSession(session)
        }
    }

    /// Takes the address a saved server is reached at now. Its accounts stay signed in, the open
    /// profile included, which reaches it there from now on.
    ///
    /// - Parameter server: the server as found at its new address. It must be the same server.
    /// - Throws: the storage error if it couldn't be saved. Nothing changes then.
    public func updateAddress(of server: ServerInfo) throws {
        guard let index = servers.firstIndex(where: { $0.id == server.id }) else { return }
        var servers = servers
        servers[index].server = server
        try store.save(servers)
        self.servers = servers
        if let session = state.session, session.server.id == server.id {
            state = .signedIn(UserSession(server: server, user: session.user, accessToken: session.accessToken))
        }
    }

    /// Forgets every server added on this device, with their profiles and the profile opened last, so
    /// the app starts over as if freshly installed. Deleting the app doesn't do this: the Keychain
    /// keeps what's saved there. Each signed-in session is then ended on its server, best effort, as
    /// when signing out.
    ///
    /// - Throws: the storage error if they couldn't be removed. Nothing changes then, since they'd
    ///   come back at the next launch.
    public func removeAllServers() async throws {
        let sessions = servers.flatMap { saved in saved.users.compactMap { saved.session(for: $0.id) } }
        try store.removeAll()
        servers = []
        lastOpenedProfile = nil
        state = .choosingProfile
        for session in sessions {
            try? await authority.endSession(session)
        }
    }

    /// Changes a saved server and saves the result. Saving is best effort here: what's lost if it
    /// fails is refreshed or redone later.
    private func update(_ serverID: MediaServer.ID, _ change: (inout MediaServer) -> Void) {
        guard let index = servers.firstIndex(where: { $0.id == serverID }) else { return }
        change(&servers[index])
        try? store.save(servers)
    }
}
