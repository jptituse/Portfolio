/// Where the app is with signing in, for the app shell to switch on.
public enum SessionState: Hashable, Sendable {
    /// Checking for a stored session at launch.
    case restoring
    /// No session: show onboarding.
    case signedOut
    case signedIn(UserSession)

    public var session: UserSession? {
        if case .signedIn(let session) = self { session } else { nil }
    }
}
