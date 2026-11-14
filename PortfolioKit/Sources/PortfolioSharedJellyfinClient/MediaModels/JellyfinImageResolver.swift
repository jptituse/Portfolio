import Foundation
import JellyfinAPI
import PortfolioShared

/// Builds the URLs of items' images on a Jellyfin server. Its image endpoints need no sign-in.
///
/// Each URL asks for the image at the size it's drawn, so the server sends no more pixels than the
/// screen shows, at full quality. It names no format: the server then sends a JPEG, or a PNG for
/// images with transparency, such as logos. (It would send lossy WebP to a client that accepts it.)
/// The image's tag changes whenever the image does, so a URL always means the same image.
public struct JellyfinImageResolver: MediaImageResolver {
    public let server: ServerInfo

    /// The quality the server encodes with, out of 100.
    static let quality = 100

    public init(server: ServerInfo) {
        self.server = server
    }

    public func url(for item: MediaItem, _ kind: MediaImageKind, pixelSize: CGSize) -> URL? {
        guard let image = item.image(kind),
            var components = URLComponents(url: server.url.appending(path: Self.path(for: image.ownerID, kind)), resolvingAgainstBaseURL: false) else {
            return nil
        }
        let width = String(Int(pixelSize.width.rounded(.up)))
        let height = String(Int(pixelSize.height.rounded(.up)))
        let size = switch kind {
        // A logo is drawn whole inside its frame.
        case .logo: [URLQueryItem(name: "maxWidth", value: width), URLQueryItem(name: "maxHeight", value: height)]
        // Anything else covers its frame. The server never enlarges an image to fill.
        case .primary, .thumb, .backdrop: [URLQueryItem(name: "fillWidth", value: width), URLQueryItem(name: "fillHeight", value: height)]
        }
        components.queryItems = [URLQueryItem(name: "tag", value: image.tag)] + size + [URLQueryItem(name: "quality", value: String(Self.quality))]
        return components.url
    }

    /// Where the `kind` image of the item with `itemID` is: the item it belongs to, which may not be
    /// the one showing it.
    private static func path(for itemID: String, _ kind: MediaImageKind) -> String {
        let images = "Items/\(itemID)/Images"
        return switch kind {
        case .primary: "\(images)/\(ImageType.primary.rawValue)"
        case .thumb: "\(images)/\(ImageType.thumb.rawValue)"
        case .logo: "\(images)/\(ImageType.logo.rawValue)"
        case .backdrop(let index): "\(images)/\(ImageType.backdrop.rawValue)/\(index)"
        }
    }
}
