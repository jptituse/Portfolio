import Foundation
import Get
import JellyfinAPI
import os
import PortfolioShared

extension JellyfinServerClient {
    /// What `item`'s page shows beyond its card: its cast and crew, studios, release, and its first
    /// version's file.
    ///
    /// - Throws: `JellyfinError.unauthorized` if the server no longer accepts the session,
    ///   `.unreachable` or `.serverError`; `CancellationError` if the task is cancelled.
    public func details(of item: MediaItem, session: UserSession) async throws -> MediaItemDetails {
        let dto = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.getItem(itemID: item.id, userID: session.user.id)).value
        }
        return MediaItemDetails(dto)
    }

    /// Items like `item`, most alike first, as the server finds them from their genres, tags and
    /// people.
    ///
    /// - Throws: as `details(of:session:)`.
    public func similarItems(to item: MediaItem, session: UserSession, limit: Int = 16) async throws -> [MediaItem] {
        let parameters = Paths.GetSimilarItemsParameters(userID: session.user.id, limit: limit, fields: Self.cardFields)
        let result = try await perform(.request) {
            try await makeClient(url: session.server.url, accessToken: session.accessToken)
                .send(Paths.getSimilarItems(itemID: item.id, parameters: parameters)).value
        }
        return (result.items ?? []).compactMap(MediaItem.init)
    }

    /// Every episode of the show `seriesID`, season by season, as the server orders them, with where
    /// the user got to in each and its file, for its format and languages. An episode the SDK can't read is left out, and logged, rather than
    /// failing the rest: its types take no value they don't know, so one newer than it, in one episode,
    /// lost a show all of them.
    ///
    /// - Throws: as `details(of:session:)`.
    public func episodes(ofShow seriesID: String, session: UserSession) async throws -> [MediaItem] {
        let parameters = Paths.GetEpisodesParameters(userID: session.user.id, fields: Self.cardFields + [.mediaSources], enableUserData: true)
        // As `Paths.getEpisodes`, read episode by episode.
        let request = Request<LenientItems>(path: "/Shows/\(seriesID)/Episodes", method: "GET", query: parameters.asQuery, id: "GetEpisodes")
        let result: LenientItems
        do {
            result = try await perform(.request) {
                try await makeClient(url: session.server.url, accessToken: session.accessToken).send(request).value
            }
        } catch {
            Self.log.error("Couldn't load the episodes of show \(seriesID, privacy: .public): \(String(describing: error), privacy: .public)")
            throw error
        }
        if let failure = result.failures.first {
            Self.log.error("Left out \(result.failures.count) of the episodes of show \(seriesID, privacy: .public) it couldn't read, the first: \(failure, privacy: .public)")
        }
        return result.items.compactMap(MediaItem.init)
    }

    static let log = Logger(subsystem: "Portfolio", category: "JellyfinServerClient")
}

/// A list of items read one by one, keeping those that can be read, and why the others couldn't.
struct LenientItems: Decodable, Sendable {
    let items: [BaseItemDto]
    let failures: [String]

    private enum CodingKeys: String, CodingKey {
        case items = "Items"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try container.decodeIfPresent([Entry].self, forKey: .items) ?? []
        items = entries.compactMap(\.item)
        failures = entries.compactMap(\.failure)
    }

    /// One item, or why it couldn't be read. Always decodes, so the list goes on past it.
    private struct Entry: Decodable {
        let item: BaseItemDto?
        let failure: String?

        init(from decoder: any Decoder) throws {
            do {
                item = try BaseItemDto(from: decoder)
                failure = nil
            } catch {
                item = nil
                failure = String(describing: error)
            }
        }
    }
}
