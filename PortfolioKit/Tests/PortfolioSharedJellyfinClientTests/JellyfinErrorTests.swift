import Foundation
import Get
import Testing

@testable import PortfolioSharedJellyfinClient

struct JellyfinErrorTests {
    @Test(arguments: [
        (URLError(.cannotConnectToHost) as any Error, RequestPhase.validation, JellyfinError.unreachable),
        (URLError(.cannotFindHost), .validation, .unreachable),
        (URLError(.timedOut), .request, .unreachable),
        (URLError(.notConnectedToInternet), .request, .unreachable),
        (URLError(.serverCertificateUntrusted), .validation, .unreachable),
        (URLError(.badServerResponse), .validation, .notJellyfinServer),
        (URLError(.badServerResponse), .request, .serverError(statusCode: nil)),
        (APIError.unacceptableStatusCode(401), .request, .unauthorized),
        (APIError.unacceptableStatusCode(403), .request, .unauthorized),
        (APIError.unacceptableStatusCode(401), .validation, .unauthorized),
        (APIError.unacceptableStatusCode(404), .validation, .notJellyfinServer),
        (APIError.unacceptableStatusCode(404), .request, .serverError(statusCode: 404)),
        (APIError.unacceptableStatusCode(500), .validation, .serverError(statusCode: 500)),
        (APIError.unacceptableStatusCode(503), .request, .serverError(statusCode: 503)),
        (DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "")), .validation, .notJellyfinServer),
        (DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "")), .request, .serverError(statusCode: nil)),
        (JellyfinError.unsupportedVersion(ServerVersion(major: 10, minor: 9, patch: 0)), .validation, .unsupportedVersion(ServerVersion(major: 10, minor: 9, patch: 0))),
    ])
    func classifies(_ error: any Error, _ phase: RequestPhase, _ expected: JellyfinError) {
        #expect(JellyfinError.classify(error, during: phase) as? JellyfinError == expected)
    }

    @Test(arguments: [URLError(.cancelled) as any Error, CancellationError()])
    func passesCancellationThrough(_ error: any Error) {
        #expect(JellyfinError.classify(error, during: .request) is CancellationError)
    }
}
