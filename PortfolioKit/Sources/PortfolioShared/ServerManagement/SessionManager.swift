import Observation

/// Owns the signed-in session for the app: restores it at launch, saves it at sign-in and clears it
/// at sign-out. The app shell observes `state`.
@MainActor
@Observable
public final class SessionManager {
    public private(set) var state: SessionState = .restoring

    private let store: SessionStore
    private let authority: any SessionAuthority

    public init(store: SessionStore, authority: any SessionAuthority) {
        self.store = store
        self.authority = authority
    }

    /// Restores the saved session, if there is one, and checks it with the server.
    ///
    /// - A session the server rejects is deleted, and the app is signed out.
    /// - If the server can't be reached, the saved session is kept: being offline shouldn't sign
    ///   anyone out.
    public func restore() async {
        guard let saved = try? store.load() else {
            state = .signedOut
            return
        }
        switch await authority.check(saved) {
        case .valid(let user):
            let refreshed = UserSession(server: saved.server, user: user, accessToken: saved.accessToken)
            try? store.save(refreshed)
            state = .signedIn(refreshed)
        case .unavailable:
            state = .signedIn(saved)
        case .revoked:
            try? store.clear()
            state = .signedOut
        }
    }

    /// Saves a session that onboarding just created and switches to the signed-in state.
    ///
    /// - Throws: the storage error if the session couldn't be saved. The state doesn't change then,
    ///   because a session that isn't saved would be lost at the next launch.
    public func signIn(_ session: UserSession) throws {
        try store.save(session)
        state = .signedIn(session)
    }

    /// Ends the session on the server, then forgets it locally.
    ///
    /// Telling the server is best effort: signing out works offline too, and the server-side session
    /// can then be revoked from its dashboard.
    public func signOut() async {
        if let session = state.session {
            try? await authority.endSession(session)
        }
        try? store.clear()
        state = .signedOut
    }
}
