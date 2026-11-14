import Foundation
import Observation
import PortfolioShared

/// The text `MediaDetailInfoView` shows for an item, already formatted.
@MainActor
@Observable
final class MediaDetailInfoViewModel {
    private(set) var title = ""
    /// Where the item's logo is, shown in place of the title, or nil to show the title.
    var logoURL: URL?
    /// "2024 · 1h 56m · PG-13 · Drama, Science Fiction", or nil when the item has none of those. An
    /// episode's starts with its number and name: "S1E5 · The Bridge · 2024 · 52m".
    private(set) var metadata: String?
    private(set) var overview: String?

    init(item: MediaItem) {
        update(with: item)
    }

    /// An episode's title is its show's, whose logo it shows; its own name goes in the metadata, after
    /// its number.
    func update(with item: MediaItem) {
        title = item.episode?.seriesName ?? item.name
        metadata = Self.metadata(for: item)
        overview = item.overview
    }

    private static func metadata(for item: MediaItem) -> String? {
        var parts: [String] = []
        if let episode = item.episode {
            if let label = episode.shortLabel { parts.append(label) }
            if !item.name.isEmpty { parts.append(item.name) }
        }
        if let year = item.productionYear { parts.append(String(year)) }
        if let runtime = item.runtime {
            parts.append(runtime.formatted(.units(allowed: [.hours, .minutes], width: .narrow)))
        }
        if let rating = item.officialRating { parts.append(rating) }
        if !item.genres.isEmpty { parts.append(item.genres.joined(separator: ", ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
