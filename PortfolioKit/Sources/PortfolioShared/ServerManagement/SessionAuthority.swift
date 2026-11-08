/// The server side of a session: whether the server still accepts it, and ending it.
///
/// Each server integration implements this; `SessionManager` stays backend-neutral.
public protocol SessionAuthority: Sendable {
    /// Asks the server whether it still accepts `session`.
    func check(_ session: UserSession) async -> SessionCheck

    /// Tells the server the session is over, so it revokes the access token.
    func endSession(_ session: UserSession) async throws
}

/// What the server said about a stored session.
public enum SessionCheck: Hashable, Sendable {
    /// The server accepts the session. Carries the user as the server knows them now, since their
    /// name or avatar may have changed.
    case valid(User)
    /// The server rejected the session: the token was revoked or has expired.
    case revoked
    /// The server couldn't answer (offline, unreachable, failing). Says nothing about the session.
    case unavailable
}
