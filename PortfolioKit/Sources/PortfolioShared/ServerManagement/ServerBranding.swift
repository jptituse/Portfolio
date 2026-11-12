import Foundation

/// How a server presents itself on its sign-in screen. Everything is optional: most servers set no
/// message or splash image, and a server without a web client has no icon to offer.
public struct ServerBranding: Hashable, Sendable {
    /// A message for people signing in, such as terms of use, in Markdown.
    public var loginMessage: String?
    /// An image the server shows on its sign-in screen.
    public var splashImageURL: URL?
    /// The server's icon, the largest its web client offers for home screens.
    public var iconURL: URL?

    public init(loginMessage: String? = nil, splashImageURL: URL? = nil, iconURL: URL? = nil) {
        self.loginMessage = loginMessage
        self.splashImageURL = splashImageURL
        self.iconURL = iconURL
    }
}
