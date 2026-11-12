/// Where the app is with signing in, for `RootView` to switch on.
public enum SessionState: Hashable, Sendable {
    /// Loading the saved servers at launch.
    case restoring
    /// No profile is open: someone picks one, or adds a server if there are none yet. Profiles signed
    /// in on this device stay signed in, ready to open.
    case choosingProfile
    case signedIn(UserSession)

    public var session: UserSession? {
        if case .signedIn(let session) = self { session } else { nil }
    }
}
