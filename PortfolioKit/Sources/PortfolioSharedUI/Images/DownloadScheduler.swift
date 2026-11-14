/// How soon an image is wanted, which decides which waiting download starts first.
public enum ImagePriority: Int, Comparable, Sendable {
    /// Ahead of time, for something that isn't showing yet.
    case low
    /// On screen, or about to be.
    case normal
    /// What the next motion shows, such as the art a card grows into.
    case high

    public static func < (lhs: ImagePriority, rhs: ImagePriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Lets a few downloads run at once and makes the rest wait, starting the most wanted waiting one each
/// time one ends, the earliest first among those wanted as much. A screen asking for a hundred posters
/// at once would otherwise keep the art a card grows into waiting behind them.
actor DownloadScheduler {
    private let limit: Int
    private var running = 0
    private var waiting: [Waiter] = []
    private var nextOrder = 0

    private struct Waiter {
        let id: String
        var priority: ImagePriority
        let order: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    init(limit: Int) {
        self.limit = limit
    }

    /// Returns once the download `id` may start.
    func acquire(_ id: String, priority: ImagePriority) async {
        if running < limit {
            running += 1
            return
        }
        let order = nextOrder
        nextOrder += 1
        await withCheckedContinuation { continuation in
            waiting.append(Waiter(id: id, priority: priority, order: order, continuation: continuation))
        }
    }

    /// A download has ended: the most wanted waiting one starts in its place.
    func release() {
        guard let next = waiting.indices.max(by: { Self.comesAfter(waiting[$0], waiting[$1]) }) else {
            running -= 1
            return
        }
        waiting.remove(at: next).continuation.resume()
    }

    /// The download `id`, if it's waiting, is wanted at least as much as `priority`.
    func raise(_ id: String, to priority: ImagePriority) {
        for index in waiting.indices where waiting[index].id == id && waiting[index].priority < priority {
            waiting[index].priority = priority
        }
    }

    /// Whether `a` should start after `b`: it's wanted less, or as much but asked for later.
    private static func comesAfter(_ a: Waiter, _ b: Waiter) -> Bool {
        a.priority != b.priority ? a.priority < b.priority : a.order > b.order
    }
}
