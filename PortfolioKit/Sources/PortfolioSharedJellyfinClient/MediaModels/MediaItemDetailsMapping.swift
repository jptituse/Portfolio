import Foundation
import JellyfinAPI
import PortfolioShared

// Conversions from jellyfin-sdk-swift DTOs to an item's details. Internal, as `MediaModelMapping` is.

extension MediaItemDetails {
    init(_ dto: BaseItemDto) {
        self.init(
            credits: (dto.people ?? []).compactMap(Credit.init),
            studios: (dto.studios ?? []).compactMap(\.name),
            releaseDate: dto.premiereDate,
            countries: dto.productionLocations ?? [],
            tagline: dto.taglines?.first,
            criticRating: dto.criticRating.map(Double.init),
            version: dto.mediaSources?.first.map(MediaVersion.init)
        )
    }
}

extension Credit {
    init?(_ dto: BaseItemPerson) {
        guard let id = dto.id, let name = dto.name else { return nil }
        self.init(personID: id, name: name, kind: Kind(dto.type), role: dto.role.flatMap { $0.isEmpty ? nil : $0 }, imageTag: dto.primaryImageTag)
    }
}

extension Person {
    /// Someone as `/Persons` lists them.
    init?(_ dto: BaseItemDto) {
        guard let id = dto.id, let name = dto.name else { return nil }
        self.init(id: id, name: name, imageTag: dto.imageTags?[ImageType.primary.rawValue])
    }
}

extension Credit.Kind {
    init(_ kind: PersonKind?) {
        switch kind {
        case .actor: self = .actor
        case .guestStar: self = .guestStar
        case .director: self = .director
        case .writer: self = .writer
        case .producer: self = .producer
        case .composer: self = .composer
        case .creator: self = .creator
        case let other?: self = .other(other.rawValue)
        case nil: self = .other("Unknown")
        }
    }
}

extension MediaVersion {
    init(_ dto: MediaSourceInfo) {
        let streams = dto.mediaStreams ?? []
        self.init(
            container: dto.container,
            size: dto.size.map(Int64.init),
            bitrate: dto.bitrate,
            video: streams.first { $0.type == .video }.map(Video.init),
            audio: streams.filter { $0.type == .audio }.map(Audio.init),
            subtitles: streams.filter { $0.type == .subtitle }.map(Subtitles.init)
        )
    }
}

extension MediaVersion.Video {
    init(_ dto: MediaStream) {
        self.init(
            codec: dto.codec,
            profile: dto.profile,
            width: dto.width,
            height: dto.height,
            frameRate: (dto.realFrameRate ?? dto.averageFrameRate).map(Double.init),
            bitDepth: dto.bitDepth,
            bitrate: dto.bitRate,
            dynamicRange: MediaVersion.DynamicRange(dto)
        )
    }
}

extension MediaVersion.DynamicRange {
    /// From the stream's range type, with its Dolby Vision configuration where it has one.
    init(_ dto: MediaStream) {
        func dolbyVision(enhancementLayer: Bool = false, fallback: Self?) -> Self {
            .dolbyVision(
                profile: dto.dvProfile,
                level: dto.dvLevel,
                compatibility: dto.dvBlSignalCompatibilityID,
                hasEnhancementLayer: enhancementLayer || dto.elPresentFlag == 1,
                fallback: fallback
            )
        }
        switch dto.videoRangeType {
        case .sdr: self = .sdr
        case .hdr10: self = .hdr10
        case .hdr10Plus: self = .hdr10Plus
        case .hlg: self = .hlg
        case .dovi, .doviInvalid: self = dolbyVision(fallback: nil)
        case .doviWithHDR10: self = dolbyVision(fallback: .hdr10)
        case .doviWithHDR10Plus: self = dolbyVision(fallback: .hdr10Plus)
        case .doviWithHLG: self = dolbyVision(fallback: .hlg)
        case .doviWithSDR: self = dolbyVision(fallback: .sdr)
        // Profile 7's base layer is HDR10.
        case .doviWithEL: self = dolbyVision(enhancementLayer: true, fallback: .hdr10)
        case .doviWithELHDR10Plus: self = dolbyVision(enhancementLayer: true, fallback: .hdr10Plus)
        case .unknown, nil: self = dto.videoRange == .hdr ? .hdr : .sdr
        }
    }
}

extension MediaVersion.Audio {
    init(_ dto: MediaStream) {
        self.init(
            title: dto.displayTitle ?? dto.title ?? "",
            language: dto.language,
            codec: dto.codec,
            profile: dto.profile,
            channels: dto.channels,
            channelLayout: dto.channelLayout,
            spatialAudio: MediaVersion.SpatialAudio(dto.audioSpatialFormat),
            isDefault: dto.isDefault ?? false,
            bitrate: dto.bitRate
        )
    }
}

extension MediaVersion.SpatialAudio {
    init?(_ format: AudioSpatialFormat?) {
        switch format {
        case .dolbyAtmos: self = .dolbyAtmos
        case .dtsx: self = .dtsX
        case .none?, nil: return nil
        }
    }
}

extension MediaVersion.Subtitles {
    init(_ dto: MediaStream) {
        self.init(
            title: dto.displayTitle ?? dto.title ?? "",
            language: dto.language,
            codec: dto.codec,
            isForced: dto.isForced ?? false,
            isForHearingImpaired: dto.isHearingImpaired ?? false,
            isText: dto.isTextSubtitleStream ?? true,
            isExternal: dto.isExternal ?? false
        )
    }
}
