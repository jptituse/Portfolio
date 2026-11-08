import Foundation
import JellyfinAPI
import PortfolioShared

// Conversions from jellyfin-sdk-swift DTOs to PortfolioShared media models. Internal on purpose: no
// SDK type crosses this module's public API.

extension Duration {
    /// Jellyfin measures time in ticks of 100 nanoseconds.
    init(ticks: Int) {
        self = .nanoseconds(Int64(ticks) * 100)
    }
}

extension ImageTags {
    init(tags: [String: String]?, backdrops: [String]?) {
        self.init(
            primary: tags?[ImageType.primary.rawValue],
            logo: tags?[ImageType.logo.rawValue],
            thumb: tags?[ImageType.thumb.rawValue],
            backdrops: backdrops ?? []
        )
    }
}

extension UserData {
    init(_ dto: UserItemDataDto?) {
        self.init(
            isPlayed: dto?.isPlayed ?? false,
            isFavorite: dto?.isFavorite ?? false,
            playbackPosition: dto?.playbackPositionTicks.map(Duration.init(ticks:)) ?? .zero,
            playCount: dto?.playCount ?? 0
        )
    }
}

extension MediaItem.Kind {
    init(_ kind: BaseItemKind?) {
        switch kind {
        case .movie: self = .movie
        case .series: self = .series
        case .season: self = .season
        case .episode: self = .episode
        case .boxSet: self = .boxSet
        case .folder, .collectionFolder: self = .folder
        case let other?: self = .other(other.rawValue)
        case nil: self = .other("Unknown")
        }
    }
}

extension MediaItem {
    init?(_ dto: BaseItemDto) {
        guard let id = dto.id else { return nil }
        self.init(
            id: id,
            name: dto.name ?? "",
            kind: Kind(dto.type),
            overview: dto.overview,
            productionYear: dto.productionYear,
            runtime: dto.runTimeTicks.map(Duration.init(ticks:)),
            officialRating: dto.officialRating,
            communityRating: dto.communityRating.map(Double.init),
            genres: dto.genres ?? [],
            images: ImageTags(tags: dto.imageTags, backdrops: dto.backdropImageTags),
            userData: UserData(dto.userData)
        )
    }
}

extension Library.Kind {
    init(_ collectionType: CollectionType?) {
        switch collectionType {
        case .movies: self = .movies
        case .tvshows: self = .tvShows
        case .music: self = .music
        case .musicvideos: self = .musicVideos
        case .homevideos: self = .homeVideos
        case .boxsets: self = .collections
        case .playlists: self = .playlists
        case .livetv: self = .liveTV
        case nil: self = .mixed
        case let other?: self = .other(other.rawValue)
        }
    }
}

extension Library {
    init?(_ dto: BaseItemDto) {
        guard let id = dto.id, let name = dto.name else { return nil }
        self.init(
            id: id,
            name: name,
            kind: Kind(dto.collectionType),
            images: ImageTags(tags: dto.imageTags, backdrops: dto.backdropImageTags)
        )
    }
}
