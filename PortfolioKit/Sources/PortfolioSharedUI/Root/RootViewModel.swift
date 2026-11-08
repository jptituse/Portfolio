import PortfolioShared

/// Decides what `RootView` shows. `SessionManager` is observable, so a view reading `destination`
/// updates whenever the session changes.
@MainActor
final class RootViewModel {
    enum Destination: Hashable {
        case launch
        case onboarding
        case main
    }

    let sessionManager: SessionManager

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    var destination: Destination {
        Self.destination(for: sessionManager.state)
    }

    nonisolated static func destination(for state: SessionState) -> Destination {
        switch state {
        case .restoring: .launch
        case .signedOut: .onboarding
        case .signedIn: .main
        }
    }

    /// Restores the saved session, unless that has already happened.
    func restoreSession() async {
        if sessionManager.state == .restoring {
            await sessionManager.restore()
        }
    }
}
