import Testing

@testable import PortfolioSharedUI

struct DownloadSchedulerTests {
    /// Waits for `count` downloads to be waiting their turn, giving the tasks asking a moment each.
    func letWaitersQueue() async {
        for _ in 0..<20 { await Task.yield() }
    }

    @Test func startsTheMostWantedWaitingDownloadFirst() async {
        let scheduler = DownloadScheduler(limit: 1)
        await scheduler.acquire("first", priority: .normal)
        let started = Started()

        let poster = Task { await scheduler.acquire("poster", priority: .normal); await started.add("poster") }
        await letWaitersQueue()
        let backdrop = Task { await scheduler.acquire("backdrop", priority: .high); await started.add("backdrop") }
        await letWaitersQueue()

        await scheduler.release()
        await backdrop.value
        await scheduler.release()
        await poster.value

        #expect(await started.order == ["backdrop", "poster"])
    }

    @Test func startsDownloadsWantedAsMuchInTheOrderAskedFor() async {
        let scheduler = DownloadScheduler(limit: 1)
        await scheduler.acquire("first", priority: .normal)
        let started = Started()

        let a = Task { await scheduler.acquire("a", priority: .normal); await started.add("a") }
        await letWaitersQueue()
        let b = Task { await scheduler.acquire("b", priority: .normal); await started.add("b") }
        await letWaitersQueue()

        await scheduler.release()
        await a.value
        await scheduler.release()
        await b.value

        #expect(await started.order == ["a", "b"])
    }

    @Test func movesUpADownloadAskedForAgainWantingItMore() async {
        let scheduler = DownloadScheduler(limit: 1)
        await scheduler.acquire("first", priority: .normal)
        let started = Started()

        let poster = Task { await scheduler.acquire("poster", priority: .normal); await started.add("poster") }
        await letWaitersQueue()
        let ahead = Task { await scheduler.acquire("ahead", priority: .low); await started.add("ahead") }
        await letWaitersQueue()
        await scheduler.raise("ahead", to: .high)

        await scheduler.release()
        await ahead.value
        await scheduler.release()
        await poster.value

        #expect(await started.order == ["ahead", "poster"])
    }

    @Test func runsUpToItsLimitAtOnce() async {
        let scheduler = DownloadScheduler(limit: 2)
        let started = Started()

        await scheduler.acquire("a", priority: .normal)
        await scheduler.acquire("b", priority: .normal)
        let c = Task { await scheduler.acquire("c", priority: .normal); await started.add("c") }
        await letWaitersQueue()
        #expect(await started.order.isEmpty)

        await scheduler.release()
        await c.value
        #expect(await started.order == ["c"])
    }
}

private actor Started {
    var order: [String] = []
    func add(_ id: String) { order.append(id) }
}
