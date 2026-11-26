import Foundation

/// How a stream the player asks for is sent: Auto, the file as it is wherever the server will send it so;
/// Original, the file as it is always; or no more than a bitrate, which a server makes a stream at when
/// the file's is higher.
public enum PlaybackQuality: Hashable, Sendable {
    case auto
    /// The file as it is, even where the server would rather make a stream, such as above its limit for
    /// connections from outside its network. It can buffer, but never loses Dolby Vision's enhancement
    /// layer or lossless audio to a transcode.
    case original
    /// In bits per second.
    case maxBitrate(Int)

    /// The highest bitrate to ask for, or nil for the file's.
    public var maxBitrate: Int? {
        if case .maxBitrate(let bitrate) = self { bitrate } else { nil }
    }

    /// "Auto", "Original", "8 Mbps", "1.5 Mbps" or "720 kbps".
    public var name: String {
        switch self {
        case .auto:
            return "Auto"
        case .original:
            return "Original"
        case .maxBitrate(let bitrate) where bitrate >= 1_000_000:
            // In tenths of a megabit, rounded, written out by hand: a menu names each quality whenever
            // it's drawn, and a number format there cost the menus' motion on an Apple TV.
            let tenths = (bitrate + 50_000) / 100_000
            return tenths % 10 == 0 ? "\(tenths / 10) Mbps" : "\(tenths / 10).\(tenths % 10) Mbps"
        case .maxBitrate(let bitrate):
            return "\(bitrate / 1000) kbps"
        }
    }

    /// The qualities to offer for a file of `bitrate`: Auto, Original, then each bitrate Jellyfin's web
    /// client offers that's below it, highest first, so each makes a stream. All of them if the bitrate
    /// isn't known.
    static func choices(forBitrate bitrate: Int?) -> [PlaybackQuality] {
        [.auto, .original] + bitrates.filter { candidate in bitrate.map { candidate < $0 } ?? true }.map(PlaybackQuality.maxBitrate)
    }

    /// The bitrates Jellyfin's web client offers.
    static let bitrates = [
        120_000_000, 80_000_000, 60_000_000, 40_000_000, 20_000_000, 15_000_000, 10_000_000, 8_000_000,
        6_000_000, 4_000_000, 3_000_000, 1_500_000, 720_000, 420_000,
    ]
}
