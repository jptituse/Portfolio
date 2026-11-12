import Observation

/// Owns the servers added on this device and who's signed in to them: loads them at launch, opens a
/// profile, saves a new sign-in, signs out, and removes them all. `RootView` observes `state`, and the profile picker
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
        servers = (try? store.load()) ?? []
        lastOpenedProfile = try? store.loadLastOpenedProfile()
        state = .choosingProfile
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
        opened(session)
    }

    /// Makes `session` the open profile, and remembers it as the one opened last. Remembering is best
    /// effort: without it, the profile picker just starts on its first profile.
    private func opened(_ session: UserSession) {
        let profile = ProfileID(serverID: session.server.id, userID: session.user.id)
        lastOpenedProfile = profile
        try? store.saveLastOpenedProfile(profile)
        state = .signedIn(session)
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
            try? await authority.endSession(session)
            update(session.server.id) { $0.accessTokens[session.user.id] = nil }
        }
        state = .choosingProfile
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
