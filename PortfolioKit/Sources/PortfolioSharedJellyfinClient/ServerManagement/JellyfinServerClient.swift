import Foundation
import JellyfinAPI
import PortfolioShared

/// Talks to Jellyfin servers before anyone is signed in: checks an address and signs a user in.
public struct JellyfinServerClient: Sendable {
    public let identity: ClientIdentity
    private let makeSessionConfiguration: @Sendable () -> URLSessionConfiguration

    public init(identity: ClientIdentity) {
        self.init(identity: identity, sessionConfiguration: { .default })
    }

    /// Lets tests route requests through a stub `URLProtocol`.
    init(identity: ClientIdentity, sessionConfiguration: @escaping @Sendable () -> URLSessionConfiguration) {
        self.identity = identity
        self.makeSessionConfiguration = sessionConfiguration
    }

    /// Checks that `url` points at a supported Jellyfin server and returns its details.
    ///
    /// - Throws: `JellyfinError.unreachable`, `.notJellyfinServer`, `.unsupportedVersion` or
    ///   `.serverError`; `CancellationError` if the task is cancelled.
    public func validateServer(at url: URL) async throws -> ServerInfo {
        let info = try await perform(.validation) {
            try await makeClient(url: url).send(Paths.getPublicSystemInfo).value
        }
        return try ServerInfo(info, url: url)
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
    private func makeClient(url: URL) -> JellyfinClient {
        JellyfinClient(
            configuration: .init(
                url: url,
                client: identity.clientName,
                deviceName: identity.deviceName,
                deviceID: identity.deviceID,
                version: identity.version
            ),
            sessionConfiguration: makeSessionConfiguration()
        )
    }

    private func perform<T>(_ phase: RequestPhase, _ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch {
            throw JellyfinError.classify(error, during: phase)
        }
    }
}
