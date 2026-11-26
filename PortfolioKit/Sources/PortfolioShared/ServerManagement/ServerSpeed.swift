/// How quickly a server answers, and how fast it sends.
public struct ServerSpeed: Hashable, Sendable {
    /// How long the server took to answer a request that asks it for nothing: the round trip.
    public let responseTime: Duration
    /// How fast it sent a sample, in bits per second, or nil if it wasn't measured, which needs a
    /// signed-in account.
    public let bitrate: Int?

    public init(responseTime: Duration, bitrate: Int?) {
        self.responseTime = responseTime
        self.bitrate = bitrate
    }
}
