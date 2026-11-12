import Foundation
import Observation
import PortfolioShared
import PortfolioSharedJellyfinClient

/// Signing in to a server, with its branding alongside. Someone picked from the server's list only
/// needs their password, or not even that if their account has none. Anyone else types their
/// username too.
@MainActor
@Observable
public final class SignInViewModel {
    public var username: String
    public var password = ""
    public private(set) var isSigningIn = false
    /// Why the last attempt didn't work, ready to show.
    public private(set) var errorMessage: String?
    private var branding = ServerBranding()

    @ObservationIgnored private let server: ServerInfo
    @ObservationIgnored private let user: User?
    @ObservationIgnored private let client: JellyfinServerClient
    @ObservationIgnored private let sessionManager: SessionManager

    /// - Parameter user: the person signing in, or nil if they'll type their username.
    init(server: ServerInfo, user: User?, client: JellyfinServerClient, sessionManager: SessionManager) {
        self.server = server
        self.user = user
        self.client = client
        self.sessionManager = sessionManager
        username = user?.name ?? ""
    }

    /// The person signing in, if they were picked.
    public var tile: ProfileTile? {
        user.map { ProfileTile(id: $0.id, name: $0.name, pictureURL: client.pictureURL(for: $0, on: server)) }
    }

    public var title: String { user?.name ?? "Sign in to \(server.name)" }

    public var prompt: String {
        switch user {
        case nil: "Enter your username and password."
        case let user? where user.hasPassword: "Enter your password for \(server.name)."
        case _?: "Your account on \(server.name) doesn't need a password."
        }
    }

    public var asksForUsername: Bool { user == nil }
    public var asksForPassword: Bool { user?.hasPassword ?? true }

    public var serverName: String { server.name }
    public var serverDetails: String { "Jellyfin \(server.version) at \(server.url.absoluteString)" }

    /// The server's message for people signing in, such as terms of use.
    public var loginMessage: AttributedString? {
        branding.loginMessage.flatMap {
            try? AttributedString(markdown: $0, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        }
    }

    /// The image the server shows on its sign-in screen, if it has one turned on.
    public var splashImageURL: URL? { branding.splashImageURL }

    /// The server's icon, if its web client offers one.
    public var serverIconURL: URL? { branding.iconURL }

    /// Whether there's a username to try. The password can be empty: Jellyfin allows accounts without one.
    public var canSignIn: Bool {
        !trimmedUsername.isEmpty
    }

    /// Loads how the server presents its sign-in screen. Without it, the server's name shows instead.
    public func loadBranding() async {
        if let branding = try? await client.branding(of: server) {
            self.branding = branding
        }
    }

    public func signIn() async {
        guard canSignIn, !isSigningIn else { return }
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }
        do {
            let session = try await client.signIn(to: server, username: user?.name ?? trimmedUsername, password: password)
            try sessionManager.signIn(session)
        } catch is CancellationError {
            return
        } catch JellyfinError.unauthorized {
            password = ""
            errorMessage = user == nil ? "The username or password is incorrect." : "That password is incorrect."
        } catch JellyfinError.unreachable {
            errorMessage = "Couldn't reach \(server.name). Check that it's still running, and try again."
        } catch is JellyfinError {
            errorMessage = "\(server.name) ran into a problem signing you in. Try again in a moment."
        } catch {
            // Only saving the session throws anything else.
            errorMessage = "Your sign-in couldn't be saved on this device. Try again."
        }
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
