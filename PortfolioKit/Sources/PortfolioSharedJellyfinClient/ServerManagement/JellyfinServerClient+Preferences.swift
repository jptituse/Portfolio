import Foundation
import JellyfinAPI
import PortfolioShared

extension JellyfinServerClient {
    /// The languages the server knows, by name, each once.
    ///
    /// - Throws: `JellyfinError.unauthorized` if the server no longer accepts the session,
    ///   `.unreachable` or `.serverError`; `CancellationError` if the task is cancelled.
    public func languages(for session: UserSession) async throws -> [Language] {
        let cultures = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.getCultures).value
        }
        var seen = Set<String>()
        return cultures
            .compactMap { culture -> Language? in
                guard let code = culture.threeLetterISOLanguageName, let name = culture.displayName ?? culture.name,
                    seen.insert(code).inserted else {
                    return nil
                }
                return Language(code: code, name: name)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The languages the account prefers to play audio and subtitles in, in its settings on the server.
    ///
    /// - Throws: as `languages(for:)`.
    public func languagePreferences(for session: UserSession) async throws -> LanguagePreferences {
        let user = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.getCurrentUser).value
        }
        // An empty preference is none.
        func preference(_ code: String?) -> String? { code.flatMap { $0.isEmpty ? nil : $0 } }
        return LanguagePreferences(
            audio: preference(user.configuration?.audioLanguagePreference),
            subtitle: preference(user.configuration?.subtitleLanguagePreference)
        )
    }
}
