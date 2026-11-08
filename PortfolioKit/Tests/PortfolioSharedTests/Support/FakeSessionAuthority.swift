import PortfolioShared
import PortfolioSharedTestSupport
import Synchronization

/// A `SessionAuthority` whose answers each test sets.
final class FakeSessionAuthority: SessionAuthority {
    private let answer: Mutex<SessionCheck>
    private let endError = Mutex<(any Error)?>(nil)
    private let ended = Mutex<[UserSession]>([])

    init(answer: SessionCheck = .unavailable) {
        self.answer = Mutex(answer)
    }

    /// Sessions that `endSession` was called with.
    var endedSessions: [UserSession] { ended.withLock { $0 } }

    func answer(_ check: SessionCheck) {
        answer.withLock { $0 = check }
    }

    func failEndSession(with error: any Error) {
        endError.withLock { $0 = error }
    }

    func check(_ session: UserSession) async -> SessionCheck {
        answer.withLock { $0 }
    }

    func endSession(_ session: UserSession) async throws {
        ended.withLock { $0.append(session) }
        if let error = endError.withLock({ $0 }) { throw error }
    }
}
