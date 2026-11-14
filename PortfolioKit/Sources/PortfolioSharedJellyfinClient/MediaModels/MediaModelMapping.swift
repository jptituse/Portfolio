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

/// An item's own images by kind. Jellyfin lists their tags by image type, and its backdrops' tags
/// apart, in order.
func mediaImages(tags: [String: String]?, backdrops: [String]?) -> [MediaImageKind: MediaImageReference] {
    var images: [MediaImageKind: MediaImageReference] = [:]
    for (kind, type) in [(MediaImageKind.primary, ImageType.primary), (.thumb, .thumb), (.logo, .logo)] {
        images[kind] = tags?[type.rawValue].map { MediaImageReference(tag: $0) }
    }
    for (index, tag) in (backdrops ?? []).enumerated() {
        images[.backdrop(index: index)] = MediaImageReference(tag: tag)
    }
    return images
}

/// An item's images, its own and, for those it lacks, the ones Jellyfin says it borrows: an episode
/// or season shows its show's thumbnail, backdrops and logo.
func mediaImages(of dto: BaseItemDto) -> [MediaImageKind: MediaImageReference] {
    var images = mediaImages(tags: dto.imageTags, backdrops: dto.backdropImageTags)
    if images[.thumb] == nil, let owner = dto.parentThumbItemID, let tag = dto.parentThumbImageTag {
        images[.thumb] = MediaImageReference(tag: tag, ownerID: owner)
    }
    if images[.logo] == nil, let owner = dto.parentLogoItemID, let tag = dto.parentLogoImageTag {
        images[.logo] = MediaImageReference(tag: tag, ownerID: owner)
    }
    if images[.backdrop()] == nil, let owner = dto.parentBackdropItemID {
        for (index, tag) in (dto.parentBackdropImageTags ?? []).enumerated() {
            images[.backdrop(index: index)] = MediaImageReference(tag: tag, ownerID: owner)
        }
    }
    return images
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
            images: mediaImages(of: dto),
            primaryImageAspectRatio: dto.primaryImageAspectRatio,
            userData: UserData(dto.userData),
            episode: dto.type == .episode
                ? EpisodeInfo(seriesName: dto.seriesName, seriesID: dto.seriesID, seasonNumber: dto.parentIndexNumber, episodeNumber: dto.indexNumber)
                : nil
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
            images: mediaImages(tags: dto.imageTags, backdrops: dto.backdropImageTags)
        )
    }
}
