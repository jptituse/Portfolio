import PortfolioSharedJellyfinClient

/// Why something couldn't be loaded from a server, in words.
enum LoadingFailure {
    /// - Parameter activity: what was being loaded, such as "loading what's new".
    static func message(for error: any Error, server: String, activity: String) -> String {
        switch error as? JellyfinError {
        case .unreachable:
            "Couldn't reach \(server). Check that it's still running, and try again."
        case .unauthorized:
            "\(server) no longer accepts this sign-in. Switch profiles to sign in again."
        case .cannotPlayDirectly:
            "\(server) can't send this as it is, and playing it another way isn't supported yet."
        default:
            "\(server) ran into a problem \(activity). Try again in a moment."
        }
    }
}
