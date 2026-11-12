import Observation
import PortfolioShared
import PortfolioSharedJellyfinClient

/// Who's signing in to a server that was just found: one of the people it lists, or someone else,
/// for anyone the server hides from its sign-in screen.
@MainActor
@Observable
public final class UserPickerViewModel {
    /// Called with the person picked, or nil for someone else.
    @ObservationIgnored var onPick: (User?) -> Void = { _ in }
    @ObservationIgnored private let server: ServerInfo
    @ObservationIgnored private let users: [User]
    @ObservationIgnored private let client: JellyfinServerClient

    init(server: ServerInfo, users: [User], client: JellyfinServerClient) {
        self.server = server
        self.users = users
        self.client = client
    }

    public var title: String { "Who's signing in to \(server.name)?" }

    public var tiles: [ProfileTile] {
        users.map { ProfileTile(id: $0.id, name: $0.name, pictureURL: client.pictureURL(for: $0, on: server)) }
    }

    public func pick(_ tileID: ProfileTile.ID) {
        guard let user = users.first(where: { $0.id == tileID }) else { return }
        onPick(user)
    }

    public func pickSomeoneElse() {
        onPick(nil)
    }
}
