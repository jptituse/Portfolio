import Foundation

/// A server address as someone typed it, and the URLs it could stand for.
///
/// An address with a scheme (`https://jellyfin.example.com`) means exactly that URL. Without one, it
/// could be a server behind an HTTPS reverse proxy or Jellyfin's own HTTP port, so HTTPS comes first
/// and then HTTP, on port 8096 unless another port was given.
public struct ServerAddress: Hashable, Sendable {
    /// The port Jellyfin serves HTTP on unless it's been changed.
    public static let defaultHTTPPort = 8096

    /// The URLs to try, most likely first.
    public let candidates: [URL]

    /// - Parameter port: a port typed on its own. It replaces any port in `text`.
    ///
    /// Nil when the text can't be a server address: it's empty, has spaces in it, has no host, or
    /// names a scheme other than HTTP or HTTPS.
    public init?(_ text: String, port: Int? = nil) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }

        if text.contains("://") {
            guard let components = URLComponents(string: text),
                let scheme = components.scheme?.lowercased(),
                ["http", "https"].contains(scheme),
                let url = Self.url(scheme: scheme, port: port ?? components.port, from: components) else {
                return nil
            }
            candidates = [url]
        } else {
            guard let components = URLComponents(string: "https://" + text),
                let https = Self.url(scheme: "https", port: port ?? components.port, from: components),
                let http = Self.url(scheme: "http", port: port ?? components.port ?? Self.defaultHTTPPort, from: components) else {
                return nil
            }
            candidates = [https, http]
        }
    }

    /// The server's URL: the typed host and path with `scheme` and `port`, without a query, a
    /// fragment or a trailing slash.
    private static func url(scheme: String, port: Int?, from typed: URLComponents) -> URL? {
        guard let host = typed.host, !host.isEmpty else { return nil }
        var path = typed.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        components.path = path
        return components.url
    }
}
