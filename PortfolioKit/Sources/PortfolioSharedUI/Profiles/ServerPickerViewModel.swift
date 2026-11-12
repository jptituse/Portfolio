import Foundation
import Observation
import PortfolioShared
import PortfolioSharedJellyfinClient

/// Someone who isn't on the profile picker yet picks their server: one already added to this device,
/// where they sign in with their username, or another one to add.
@MainActor
@Observable
public final class ServerPickerViewModel {
    /// Each server's icon, once its web client has said where it is.
    private var iconURLs: [MediaServer.ID: URL] = [:]

    /// Called with the server picked.
    @ObservationIgnored var onPick: (ServerInfo) -> Void = { _ in }
    @ObservationIgnored var onAddServer: () -> Void = {}
    @ObservationIgnored private let client: JellyfinServerClient
    @ObservationIgnored private let sessionManager: SessionManager

    init(client: JellyfinServerClient, sessionManager: SessionManager) {
        self.client = client
        self.sessionManager = sessionManager
    }

    public var title: String { "Which server are you on?" }

    /// Each server added to this device, with its icon and its address under its name.
    public var tiles: [ProfileTile] {
        sessionManager.servers.map { saved in
            ProfileTile(id: saved.id, name: saved.server.name, detail: Self.address(of: saved.server), pictureURL: iconURLs[saved.id])
        }
    }

    public func pick(_ tileID: ProfileTile.ID) {
        guard let saved = sessionManager.servers.first(where: { $0.id == tileID }) else { return }
        onPick(saved.server)
    }

    public func addServer() {
        onAddServer()
    }

    /// Asks each server's web client for its icon. Servers without one show their initials.
    public func loadIcons() async {
        for saved in sessionManager.servers where iconURLs[saved.id] == nil {
            if let iconURL = await client.iconURL(of: saved.server) {
                iconURLs[saved.id] = iconURL
            }
        }
    }

    /// The server's address without its scheme, such as "192.168.1.10:8096".
    private static func address(of server: ServerInfo) -> String {
        let url = server.url.absoluteString
        guard let scheme = url.range(of: "://") else { return url }
        return String(url[scheme.upperBound...])
    }
}
