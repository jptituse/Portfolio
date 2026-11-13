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
    /// "2024 · 1h 56m · PG-13 · Drama, Science Fiction", or nil when the item has none of those.
    private(set) var metadata: String?
    private(set) var overview: String?

    init(item: MediaItem) {
        update(with: item)
    }

    func update(with item: MediaItem) {
        title = item.name
        metadata = Self.metadata(for: item)
        overview = item.overview
    }

    private static func metadata(for item: MediaItem) -> String? {
        var parts: [String] = []
        if let year = item.productionYear { parts.append(String(year)) }
        if let runtime = item.runtime {
            parts.append(runtime.formatted(.units(allowed: [.hours, .minutes], width: .narrow)))
        }
        if let rating = item.officialRating { parts.append(rating) }
        if !item.genres.isEmpty { parts.append(item.genres.joined(separator: ", ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
