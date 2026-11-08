import Foundation
import Get
import JellyfinAPI

/// Why a request to a Jellyfin server failed, in terms the UI can explain to the user.
///
/// Cancellation is never reported as a `JellyfinError`: a cancelled request throws `CancellationError`.
public enum JellyfinError: Error, Hashable, Sendable {
    /// Nothing answered at that address (wrong host or port, server down, no network, TLS failure).
    case unreachable
    /// Something answered, but it isn't a Jellyfin server.
    case notJellyfinServer
    /// A Jellyfin server older than `ServerVersion.minimumSupported`.
    case unsupportedVersion(ServerVersion)
    /// Wrong username or password, or an access token the server no longer accepts.
    case unauthorized
    /// The server failed the request. `statusCode` is nil when the response itself was unusable.
    case serverError(statusCode: Int?)
}

/// Which kind of request failed, since the same failure means different things for each.
enum RequestPhase {
    /// Probing an address to find out whether it's a Jellyfin server.
    case validation
    /// Any request to a server already known to be Jellyfin.
    case request
}

extension JellyfinError {
    /// Maps an error thrown by the SDK, `Get` or `URLSession` to a `JellyfinError`, passing
    /// cancellation through as `CancellationError`.
    static func classify(_ error: any Error, during phase: RequestPhase) -> any Error {
        switch error {
        case let error as JellyfinError:
            return error
        case is CancellationError:
            return error
        case let error as URLError:
            return error.code == .cancelled ? CancellationError() : classify(error, during: phase)
        case APIError.unacceptableStatusCode(let statusCode):
            return classify(statusCode: statusCode, during: phase)
        case is DecodingError:
            return phase == .validation ? JellyfinError.notJellyfinServer : JellyfinError.serverError(statusCode: nil)
        default:
            return JellyfinError.serverError(statusCode: nil)
        }
    }

    private static func classify(_ error: URLError, during phase: RequestPhase) -> JellyfinError {
        switch error.code {
        case .badServerResponse, .cannotParseResponse, .cannotDecodeContentData, .cannotDecodeRawData:
            return phase == .validation ? .notJellyfinServer : .serverError(statusCode: nil)
        default:
            return .unreachable
        }
    }

    private static func classify(statusCode: Int, during phase: RequestPhase) -> JellyfinError {
        switch statusCode {
        case 401, 403:
            return .unauthorized
        case 400..<500 where phase == .validation:
            // A missing /System/Info/Public means some other web server answered.
            return .notJellyfinServer
        default:
            return .serverError(statusCode: statusCode)
        }
    }
}
