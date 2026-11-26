import Foundation
import JellyfinAPI
import PortfolioShared

extension JellyfinServerClient {
    /// Measures how quickly the server answers and, with a signed-in account, how fast it sends: the
    /// quickest of a few requests that ask it for nothing, then a sample of `sampleSize` bytes.
    ///
    /// - Parameter session: an account signed in on the server, to measure how fast it sends.
    /// - Throws: `JellyfinError.unreachable` or `.serverError`, also if the account is no longer
    ///   accepted; `CancellationError` if the task is cancelled.
    public func measureSpeed(of server: ServerInfo, session: UserSession?, sampleSize: Int = speedTestSampleSize) async throws -> ServerSpeed {
        let clock = ContinuousClock()
        var responseTime = Duration.seconds(Int64.max)
        for _ in 0..<Self.speedTestPings {
            let start = clock.now
            _ = try await perform(.request) {
                try await makeClient(url: server.url, timeout: Self.validationTimeout).send(Paths.getPingSystem).value
            }
            responseTime = min(responseTime, clock.now - start)
        }
        guard let session else { return ServerSpeed(responseTime: responseTime, bitrate: nil) }
        let start = clock.now
        let sample = try await perform(.request) {
            try await makeClient(url: server.url, accessToken: session.accessToken)
                .send(Paths.getBitrateTestBytes(size: sampleSize)).value
        }
        let seconds = (clock.now - start).inSeconds
        let bitrate = seconds > 0 ? Int(Double(sample.count * 8) / seconds) : nil
        return ServerSpeed(responseTime: responseTime, bitrate: bitrate)
    }

    /// How many bytes a speed test downloads: enough to take a moment even on a fast home network.
    public static let speedTestSampleSize = 20_000_000
    static let speedTestPings = 3
}

private extension Duration {
    var inSeconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
