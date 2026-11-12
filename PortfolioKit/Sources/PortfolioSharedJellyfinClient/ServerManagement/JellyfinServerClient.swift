import Foundation
import JellyfinAPI
import PortfolioShared

/// Talks to Jellyfin servers about servers and sessions: checks an address, signs a user in, and
/// (as the app's `SessionAuthority`) checks and ends saved sessions.
public struct JellyfinServerClient: Sendable {
    public let identity: ClientIdentity
    private let makeSessionConfiguration: @Sendable () -> URLSessionConfiguration

    public init(identity: ClientIdentity) {
        self.init(identity: identity, sessionConfiguration: { .default })
    }

    /// Lets tests route requests through a stub `URLProtocol`.
    package init(identity: ClientIdentity, sessionConfiguration: @escaping @Sendable () -> URLSessionConfiguration) {
        self.identity = identity
        self.makeSessionConfiguration = sessionConfiguration
    }

    /// How long checking an address waits for an answer. Much shorter than the system's default, so
    /// an address that silently drops connections fails in seconds rather than a minute.
    static let validationTimeout: TimeInterval = 10

    /// Checks that `url` points at a supported Jellyfin server and returns its details.
    ///
    /// - Throws: `JellyfinError.unreachable`, `.notJellyfinServer`, `.unsupportedVersion` or
    ///   `.serverError`; `CancellationError` if the task is cancelled.
    public func validateServer(at url: URL) async throws -> ServerInfo {
        let info = try await perform(.validation) {
            try await makeClient(url: url, timeout: Self.validationTimeout).send(Paths.getPublicSystemInfo).value
        }
        return try ServerInfo(info, url: url)
    }

    /// Finds the server at a typed address: tries each URL it could stand for, in order, and returns
    /// the first that's a supported Jellyfin server.
    ///
    /// - Throws: the most telling failure among the URLs tried. `.unsupportedVersion` is thrown at
    ///   once, since that URL is a Jellyfin server; otherwise `.unauthorized`, `.serverError`,
    ///   `.notJellyfinServer` and `.unreachable` come in that order. `CancellationError` if the task
    ///   is cancelled.
    public func validateServer(at address: ServerAddress) async throws -> ServerInfo {
        var failure = JellyfinError.unreachable
        for url in address.candidates {
            do {
                return try await validateServer(at: url)
            } catch let error as JellyfinError {
                if case .unsupportedVersion = error { throw error }
                if error.specificity > failure.specificity { failure = error }
            }
        }
        throw failure
    }

    /// The users the server lists on its sign-in screen, in its order. Users set to be hidden from it
    /// aren't included, and a server can hide everyone.
    ///
    /// - Throws: `JellyfinError.unreachable` or `.serverError`; `CancellationError` if the task is
    ///   cancelled.
    public func listedUsers(on server: ServerInfo) async throws -> [User] {
        let users = try await perform(.request) {
            try await makeClient(url: server.url).send(Paths.getPublicUsers).value
        }
        return users.compactMap(User.init)
    }

    /// How the server presents its sign-in screen. Its icon is best effort: a server without its web
    /// client has none, and still has the rest.
    ///
    /// - Throws: `JellyfinError.unreachable` or `.serverError`; `CancellationError` if the task is
    ///   cancelled.
    public func branding(of server: ServerInfo) async throws -> ServerBranding {
        async let iconURL = iconURL(of: server)
        let options = try await perform(.request) {
            try await makeClient(url: server.url).send(Paths.getBrandingOptions).value
        }
        var branding = ServerBranding(options, server: server)
        branding.iconURL = await iconURL
        return branding
    }

    /// The server's icon: the largest its web client offers for home screens, or nil if there isn't
    /// one, such as when the web client is turned off or can't be reached. It's the web client's own
    /// file, not the API, so it isn't asked for through the SDK.
    public func iconURL(of server: ServerInfo) async -> URL? {
        let webClient = server.url.appending(path: "web", directoryHint: .isDirectory)
        let configuration = makeSessionConfiguration()
        configuration.timeoutIntervalForRequest = Self.validationTimeout
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(from: webClient.appending(path: "manifest.json")),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let manifest = try? JSONDecoder().decode(WebAppManifest.self, from: data),
            let icon = manifest.icons.max(by: { $0.width < $1.width }) else {
            return nil
        }
        return URL(string: icon.src, relativeTo: webClient)?.absoluteURL
    }

    /// Where the user's picture is, or nil if they haven't set one. Anyone can load it, signed in or
    /// not, as the server's own sign-in screen does.
    public func pictureURL(for user: User, on server: ServerInfo) -> URL? {
        guard let tag = user.primaryImageTag else { return nil }
        return Self.imageURL("UserImage", on: server, query: [
            URLQueryItem(name: "userId", value: user.id),
            URLQueryItem(name: "tag", value: tag),
        ])
    }

    /// An image at `path` on the server, in the best quality it can send. Its image endpoints have no
    /// size or quality options, so it sends the image at its full size. Asking for PNG keeps it from
    /// compressing the image again on the way: left to choose, it may pick lossy WebP or JPEG.
    static func imageURL(_ path: String, on server: ServerInfo, query: [URLQueryItem] = []) -> URL? {
        guard var components = URLComponents(url: server.url.appending(path: path), resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = query + [URLQueryItem(name: "format", value: ImageFormat.png.rawValue)]
        return components.url
    }

    /// Signs a user in with their username and password.
    ///
    /// - Throws: `JellyfinError.unauthorized` for wrong credentials, `.unreachable` or `.serverError`;
    ///   `CancellationError` if the task is cancelled.
    public func signIn(to server: ServerInfo, username: String, password: String) async throws -> UserSession {
        let result = try await perform(.request) {
            try await makeClient(url: server.url).signIn(username: username, password: password)
        }
        guard let token = result.accessToken, let dto = result.user, let user = User(dto) else {
            throw JellyfinError.serverError(statusCode: nil)
        }
        return UserSession(server: server, user: user, accessToken: token)
    }

    /// A fresh SDK client per operation: the SDK's client stores the access token in mutable state,
    /// so instances are never shared.
    func makeClient(url: URL, accessToken: String? = nil, timeout: TimeInterval? = nil) -> JellyfinClient {
        let sessionConfiguration = makeSessionConfiguration()
        if let timeout {
            sessionConfiguration.timeoutIntervalForRequest = timeout
        }
        return JellyfinClient(
            configuration: .init(
                url: url,
                accessToken: accessToken,
                client: identity.clientName,
                deviceName: identity.deviceName,
                deviceID: identity.deviceID,
                version: identity.version
            ),
            sessionConfiguration: sessionConfiguration
        )
    }

    func perform<T>(_ phase: RequestPhase, _ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw JellyfinError.classify(error, during: phase)
        }
    }
}
