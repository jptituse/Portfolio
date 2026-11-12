import Foundation
import JellyfinAPI
import PortfolioShared

// Conversions from jellyfin-sdk-swift DTOs to PortfolioShared server and user models. Internal on
// purpose: no SDK type crosses this module's public API.

extension User {
    init?(_ dto: UserDto) {
        guard let id = dto.id, let name = dto.name else { return nil }
        self.init(
            id: id,
            name: name,
            serverID: dto.serverID,
            primaryImageTag: dto.primaryImageTag,
            hasPassword: dto.hasPassword ?? true
        )
    }
}

extension ServerBranding {
    /// The splash image is only used if the server has it turned on.
    init(_ dto: BrandingOptionsDto, server: ServerInfo) {
        let message = dto.loginDisclaimer?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            loginMessage: message?.isEmpty == false ? message : nil,
            splashImageURL: dto.isSplashscreenEnabled == true ? JellyfinServerClient.imageURL("Branding/Splashscreen", on: server) : nil
        )
    }
}

extension ServerInfo {
    /// Validates the public system info: it must come from a Jellyfin server new enough to support.
    init(_ dto: PublicSystemInfo, url: URL) throws(JellyfinError) {
        if let product = dto.productName, !product.localizedCaseInsensitiveContains("jellyfin") {
            throw .notJellyfinServer
        }
        guard let id = dto.id, let versionString = dto.version, let version = ServerVersion(versionString) else {
            throw .notJellyfinServer
        }
        guard version.isSupported else { throw .unsupportedVersion(version) }
        self.init(id: id, name: dto.serverName ?? "Jellyfin", version: versionString, url: url)
    }
}
