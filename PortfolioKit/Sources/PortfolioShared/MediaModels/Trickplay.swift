import CoreGraphics
import Foundation

/// Pictures of a video at a steady interval, to show where scrubbing would take it, as a server makes
/// them: laid out in rows on a series of tile images, each `columns` pictures across and `rows` down,
/// the first picture at the video's start.
public struct Trickplay: Hashable, Sendable {
    /// The tile images, in order.
    public let tileURLs: [URL]
    /// What the tiles need sent with them, such as to sign in.
    public let httpHeaders: [String: String]
    /// One picture's size, in pixels.
    public let pictureWidth: Int
    public let pictureHeight: Int
    public let columns: Int
    public let rows: Int
    /// How many pictures there are.
    public let count: Int
    /// How far apart in the video the pictures are.
    public let interval: Duration

    public init(
        tileURLs: [URL],
        httpHeaders: [String: String] = [:],
        pictureWidth: Int,
        pictureHeight: Int,
        columns: Int,
        rows: Int,
        count: Int,
        interval: Duration
    ) {
        self.tileURLs = tileURLs
        self.httpHeaders = httpHeaders
        self.pictureWidth = pictureWidth
        self.pictureHeight = pictureHeight
        self.columns = columns
        self.rows = rows
        self.count = count
        self.interval = interval
    }

    /// The pictures' shape, width over height.
    public var aspectRatio: Double {
        pictureHeight > 0 ? Double(pictureWidth) / Double(pictureHeight) : 16.0 / 9
    }

    /// The picture for `time`, the last taken at or before it: which tile it's on, and where.
    public func picture(at time: Duration) -> Picture? {
        guard count > 0, interval > .zero, columns > 0, rows > 0 else { return nil }
        let index = min(max(Int((time / interval).rounded(.down)), 0), count - 1)
        let onEachTile = columns * rows
        let tile = index / onEachTile
        guard tile < tileURLs.count else { return nil }
        let place = index % onEachTile
        let rect = CGRect(
            x: place % columns * pictureWidth,
            y: place / columns * pictureHeight,
            width: pictureWidth,
            height: pictureHeight
        )
        return Picture(index: index, tileURL: tileURLs[tile], rect: rect)
    }

    /// One of the pictures: which, from 0, and where it is on its tile, in pixels from the top left.
    public struct Picture: Hashable, Sendable {
        public let index: Int
        public let tileURL: URL
        public let rect: CGRect
    }
}
