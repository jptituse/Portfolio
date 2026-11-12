import Observation
import PortfolioShared
import PortfolioSharedJellyfinClient

/// "Who's watching?": everyone on the servers added to this device, signed in or not. Picking a
/// signed-in profile opens it; anyone else signs in first. Someone who isn't here picks their server
/// next, or adds it.
@MainActor
@Observable
public final class ProfilePickerViewModel {
    /// The profile being opened, while its session is checked with the server.
    private var openingProfile: ProfileTile.ID?

    @ObservationIgnored var onSomeoneElse: () -> Void = {}
    /// Called with a profile that has to sign in first.
    @ObservationIgnored var onSignIn: (ServerInfo, User) -> Void = { _, _ in }
    @ObservationIgnored private let client: JellyfinServerClient
    @ObservationIgnored private let sessionManager: SessionManager

    init(client: JellyfinServerClient, sessionManager: SessionManager) {
        self.client = client
        self.sessionManager = sessionManager
    }

    /// Everyone on every server, server by server, with the server's name under each.
    public var tiles: [ProfileTile] {
        sessionManager.servers.flatMap { saved in
            saved.users.map { user in
                ProfileTile(
                    id: Self.tileID(user: user.id, server: saved.id),
                    name: user.name,
                    detail: saved.server.name,
                    pictureURL: client.pictureURL(for: user, on: saved.server)
                )
            }
        }
    }

    /// The tile to start on: the profile opened last, if it's still here. It's only highlighted, so
    /// someone else can still pick theirs.
    public var initialFocus: ProfileTile.ID? {
        guard let last = sessionManager.lastOpenedProfile else { return nil }
        let tileID = Self.tileID(user: last.userID, server: last.serverID)
        return tiles.contains { $0.id == tileID } ? tileID : nil
    }

    public func isOpening(_ tileID: ProfileTile.ID) -> Bool {
        openingProfile == tileID
    }

    /// Opens a signed-in profile, which takes the app to its Home. A profile that's signed out, or
    /// whose sign-in the server no longer accepts, signs in first.
    public func open(_ tileID: ProfileTile.ID) async {
        guard openingProfile == nil, let (saved, user) = profile(for: tileID) else { return }
        if saved.isSignedIn(user.id) {
            openingProfile = tileID
            let opened = await sessionManager.open(user.id, on: saved.id)
            openingProfile = nil
            if opened { return }
        }
        onSignIn(saved.server, user)
    }

    /// For someone who isn't on the picker: they pick their server next.
    public func someoneElse() {
        onSomeoneElse()
    }

    /// Asks each server who it lists now, so new people and new pictures show up. A server that can't
    /// be reached keeps what was saved.
    public func refresh() async {
        for saved in sessionManager.servers {
            if let users = try? await client.listedUsers(on: saved.server) {
                sessionManager.updateListedUsers(users, on: saved.id)
            }
        }
    }

    private func profile(for tileID: ProfileTile.ID) -> (MediaServer, User)? {
        for saved in sessionManager.servers {
            if let user = saved.users.first(where: { Self.tileID(user: $0.id, server: saved.id) == tileID }) {
                return (saved, user)
            }
        }
        return nil
    }

    private static func tileID(user: User.ID, server: MediaServer.ID) -> ProfileTile.ID {
        "\(server)/\(user)"
    }
}
