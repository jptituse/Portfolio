import Foundation
import JellyfinAPI
import PortfolioShared

extension JellyfinServerClient {
    /// The pictures the server has made of `item`'s version `versionID` (its default, without one) at a
    /// steady interval, to show where scrubbing would take it, or nil if it has made none: at the
    /// smallest width at least `pixelWidth` wide, else the widest, of those whose tiles have no more
    /// than `tilePixelLimit` pixels. Jellyfin makes them (10.9 and later) where a library has trickplay
    /// images turned on, 320 pixels wide unless set otherwise, on tiles of 10 by 10.
    ///
    /// - Parameter tilePixelLimit: the most pixels a tile may have. A tile is decoded whole, at 4 bytes a
    ///   pixel: tiles of 640-pixel pictures are 92 MB, and 1280's four times that.
    /// - Throws: as `details(of:session:)`.
    public func trickplay(
        for item: MediaItem,
        versionID: String?,
        pixelWidth: Int,
        tilePixelLimit: Int = 24_000_000,
        session: UserSession
    ) async throws -> Trickplay? {
        let dto = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.getItem(itemID: item.id, userID: session.user.id)).value
        }
        let sourceID = versionID ?? item.id
        // Without a version named, the item's own, else any.
        guard let widths = dto.trickplay?[sourceID] ?? (versionID == nil ? dto.trickplay?.values.first : nil) else {
            return nil
        }
        let sizes = widths.compactMap { key, info in Int(key).map { ($0, info) } }
            .filter { _, info in
                (info.width ?? 0) * (info.tileWidth ?? 0) * (info.height ?? 0) * (info.tileHeight ?? 0) <= tilePixelLimit
            }
            .sorted { $0.0 < $1.0 }
        guard let (width, info) = sizes.first(where: { $0.0 >= pixelWidth }) ?? sizes.last,
            let pictureWidth = info.width, let pictureHeight = info.height,
            let columns = info.tileWidth, let rows = info.tileHeight,
            let count = info.thumbnailCount, let interval = info.interval,
            columns > 0, rows > 0, count > 0, interval > 0 else {
            return nil
        }
        let tiles = (count + columns * rows - 1) / (columns * rows)
        let tileURLs = (0..<tiles).compactMap { index in
            Self.trickplayTileURL(for: item.id, width: width, index: index, sourceID: sourceID, on: session.server)
        }
        return Trickplay(
            tileURLs: tileURLs,
            httpHeaders: ["Authorization": identity.authorizationHeader(accessToken: session.accessToken)],
            pictureWidth: pictureWidth,
            pictureHeight: pictureHeight,
            columns: columns,
            rows: rows,
            count: count,
            interval: .milliseconds(interval)
        )
    }

    /// Where the server sends a tile of an item's trickplay pictures, which needs the user signed in.
    static func trickplayTileURL(for itemID: String, width: Int, index: Int, sourceID: String, on server: ServerInfo) -> URL? {
        let path = server.url.appending(path: "Videos/\(itemID)/Trickplay/\(width)/\(index).jpg")
        guard var components = URLComponents(url: path, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "mediaSourceId", value: sourceID)]
        return components.url
    }
}
