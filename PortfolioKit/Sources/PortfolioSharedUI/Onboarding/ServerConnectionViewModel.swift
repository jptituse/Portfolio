import Foundation
import Observation
import PortfolioShared
import PortfolioSharedJellyfinClient

/// Adding a server: the address and port someone types, checking that a supported Jellyfin server
/// is there, and finding out who it lists on its sign-in screen.
@MainActor
@Observable
public final class ServerConnectionViewModel {
    public var address = ""
    /// Optional: without one, the usual ports are tried.
    public var port = ""
    public private(set) var isConnecting = false
    /// Why the last try didn't work, ready to show.
    public private(set) var errorMessage: String?

    /// Called with the server, and the users it lists, once one is found.
    @ObservationIgnored var onConnect: (ServerInfo, [User]) -> Void = { _, _ in }
    @ObservationIgnored private let client: JellyfinServerClient

    init(client: JellyfinServerClient) {
        self.client = client
    }

    /// Whether there's an address to try.
    public var canConnect: Bool {
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func connect() async {
        guard canConnect, !isConnecting else { return }
        let portText = port.trimmingCharacters(in: .whitespacesAndNewlines)
        let portNumber = Int(portText)
        if !portText.isEmpty, portNumber.map(Self.ports.contains) != true {
            errorMessage = "The port is a number from 1 to 65535, such as 8096."
            return
        }
        guard let serverAddress = ServerAddress(address, port: portNumber) else {
            errorMessage = "Enter your server's address, such as 192.168.1.10 or jellyfin.example.com."
            return
        }
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }
        do {
            let server = try await client.validateServer(at: serverAddress)
            // A server that won't list its users still works: everyone types their username.
            let users = (try? await client.listedUsers(on: server)) ?? []
            onConnect(server, users)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private static let ports = 1...65535

    private static func message(for error: any Error) -> String {
        switch error as? JellyfinError {
        case .unreachable:
            return "Couldn't reach a server at that address. Check the address and port, and that the server is running."
        case .notJellyfinServer:
            return "There's a server at that address, but it isn't Jellyfin."
        case .unsupportedVersion(let version):
            let minimum = ServerVersion.minimumSupported
            return "This server runs Jellyfin \(version). Portfolio needs Jellyfin \(minimum.major).\(minimum.minor) or later."
        case .unauthorized:
            return "The server asked for a password before Portfolio could reach Jellyfin. Try the server's own address instead."
        case .serverError, nil:
            return "The server ran into a problem. Try again in a moment."
        }
    }
}
