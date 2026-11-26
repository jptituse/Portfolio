import Observation
import PortfolioShared
import PortfolioSharedJellyfinClient

/// Everything before someone is signed in. With servers added, it opens on the profile picker;
/// without, on the welcome screen. Adding a server goes from the welcome screen to the server's
/// address, who's signing in, and their password. Someone not on the profile picker picks their
/// server first, or adds it.
///
/// Settings starts the same steps to add a server or an account (`adding(_:client:sessionManager:)`),
/// which save the account without opening it, so the open profile stays open.
@MainActor
@Observable
public final class ProfilesViewModel {
    /// A step pushed on the navigation path, with its view model.
    public enum Step: Hashable {
        case servers(ServerPickerViewModel)
        case welcome
        case server(ServerConnectionViewModel)
        case users(UserPickerViewModel)
        case signIn(SignInViewModel)

        // Navigation values have to be Hashable. A step is equal only to itself, by its view model,
        // so two steps showing the same content stay two entries on the path.
        public static func == (lhs: Step, rhs: Step) -> Bool {
            switch (lhs, rhs) {
            case (.welcome, .welcome): true
            default: lhs.viewModel === rhs.viewModel
            }
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(viewModel.map(ObjectIdentifier.init))
        }

        /// The step's view model. The welcome screen has none.
        private var viewModel: AnyObject? {
            switch self {
            case .servers(let viewModel): viewModel
            case .welcome: nil
            case .server(let viewModel): viewModel
            case .users(let viewModel): viewModel
            case .signIn(let viewModel): viewModel
            }
        }
    }

    /// The first screen, under the steps.
    public enum First {
        case picker(ProfilePickerViewModel)
        case welcome
        case servers(ServerPickerViewModel)
    }

    /// What Settings adds.
    public enum Addition {
        /// A server, from the welcome screen.
        case server
        /// An account, on a server already added or a new one, from picking the server.
        case account
    }

    /// The steps on top of the first screen. Going back pops them.
    public var path: [Step] = []
    public private(set) var first: First = .welcome

    /// Called once an account added from Settings is saved.
    @ObservationIgnored public var onAdded: () -> Void = {}
    @ObservationIgnored private let client: JellyfinServerClient
    @ObservationIgnored private let sessionManager: SessionManager
    /// Whether signing in opens the profile, as it does before anyone is signed in, or only saves it.
    @ObservationIgnored private let opensProfile: Bool

    init(client: JellyfinServerClient, sessionManager: SessionManager) {
        self.client = client
        self.sessionManager = sessionManager
        opensProfile = true
        if !sessionManager.servers.isEmpty {
            let picker = ProfilePickerViewModel(client: client, sessionManager: sessionManager)
            picker.onSomeoneElse = { [weak self] in self?.pickServer() }
            picker.onSignIn = { [weak self] server, user in self?.signIn(to: server, as: user) }
            first = .picker(picker)
        }
    }

    private init(adding addition: Addition, client: JellyfinServerClient, sessionManager: SessionManager) {
        self.client = client
        self.sessionManager = sessionManager
        opensProfile = false
        if addition == .account {
            first = .servers(makeServerPicker())
        }
    }

    /// The steps for adding a server or an account from Settings. The account is saved without opening
    /// it, then `onAdded` is called.
    public static func adding(_ addition: Addition, client: JellyfinServerClient, sessionManager: SessionManager) -> ProfilesViewModel {
        ProfilesViewModel(adding: addition, client: client, sessionManager: sessionManager)
    }

    /// The profile picker, once a server has been added. Without one, the welcome screen comes first.
    public var picker: ProfilePickerViewModel? {
        if case .picker(let picker) = first { picker } else { nil }
    }

    /// Someone not on the profile picker: they're on a server already added, where they type their
    /// username (anyone it lists is on the picker already), or on another one to add.
    private func pickServer() {
        path.append(.servers(makeServerPicker()))
    }

    private func makeServerPicker() -> ServerPickerViewModel {
        let step = ServerPickerViewModel(client: client, sessionManager: sessionManager)
        step.onPick = { [weak self] server in self?.signIn(to: server, as: nil) }
        step.onAddServer = { [weak self] in self?.path.append(.welcome) }
        return step
    }

    /// From the welcome screen: add a server by its address.
    public func addServerByAddress() {
        let step = ServerConnectionViewModel(client: client)
        step.onConnect = { [weak self] server, users in self?.found(server, listing: users) }
        path.append(.server(step))
    }

    /// A server that lists nobody goes straight to signing in with a username.
    private func found(_ server: ServerInfo, listing users: [User]) {
        guard !users.isEmpty else {
            signIn(to: server, as: nil)
            return
        }
        let step = UserPickerViewModel(server: server, users: users, client: client)
        step.onPick = { [weak self] user in self?.signIn(to: server, as: user) }
        path.append(.users(step))
    }

    private func signIn(to server: ServerInfo, as user: User?) {
        let step = SignInViewModel(server: server, user: user, client: client, sessionManager: sessionManager, opensProfile: opensProfile)
        step.onSignedIn = { [weak self] in self?.onAdded() }
        path.append(.signIn(step))
    }

    #if DEBUG
    /// Signs in with a sample session, so the signed-in app can be explored without a server. Its
    /// server doesn't exist, so the app stays signed in offline.
    public func continueWithSampleSession() {
        try? sessionManager.signIn(.preview)
    }
    #endif
}
