import Foundation
import Synchronization

/// An in-process stand-in for a Jellyfin server, for unit tests.
///
/// It answers the endpoints the client uses with responses shaped like a real server's, checks
/// credentials against its accounts, tracks the access tokens it issued, and records every request.
/// Requests never leave the process: `MockJellyfinServer.sessionConfiguration` routes each one to the
/// server listening at its scheme, host and port. Each instance gets its own host unless it's given
/// a URL, so tests can run in parallel.
public final class MockJellyfinServer: Sendable {
    public struct Account: Sendable {
        public var name: String
        public var password: String
        /// Hidden from the server's sign-in screen, so it isn't in `/Users/Public`.
        public var isHidden: Bool
        /// The account's picture, if it has one.
        public var imageTag: String?
        public var id = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")

        public init(name: String, password: String, isHidden: Bool = false, imageTag: String? = nil) {
            self.name = name
            self.password = password
            self.isHidden = isHidden
            self.imageTag = imageTag
        }
    }

    /// An item in the server's libraries.
    public struct Item: Sendable {
        public var name: String
        /// The Jellyfin item type, such as `Movie` or `Series`.
        public var type: String
        /// The tags of the item's images by Jellyfin image type, such as `Primary` or `Thumb`.
        public var imageTags: [String: String]
        public var backdropTags: [String]
        /// The shape of its primary image, width over height.
        public var primaryImageAspectRatio: Double?
        public var id = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")

        public init(
            name: String,
            type: String = "Movie",
            imageTags: [String: String] = [:],
            backdropTags: [String] = [],
            primaryImageAspectRatio: Double? = nil
        ) {
            self.name = name
            self.type = type
            self.imageTags = imageTags
            self.backdropTags = backdropTags
            self.primaryImageAspectRatio = primaryImageAspectRatio
        }
    }

    /// How the server responds.
    public enum Behavior: Sendable {
        /// Behaves like a working Jellyfin server.
        case jellyfin
        /// Nothing is listening: every request fails to connect.
        case offline
        /// Some other web server: every request gets this status and an HTML page.
        case otherWebServer(status: Int)
        /// A Jellyfin server that fails every request with this status.
        case failing(status: Int)
    }

    /// Where the server listens. Its scheme, host and port are all it answers on.
    public let url: URL
    public let id: String
    public let name: String
    public let version: String
    public let productName: String
    public let accounts: [Account]
    public let behavior: Behavior
    /// The branding the admin set: a sign-in message, and whether the splash image is on.
    public let loginDisclaimer: String?
    public let splashscreenEnabled: Bool
    /// Whether the server hosts its web client, whose manifest lists the server's icons.
    public let hostsWebClient: Bool
    /// The items in its libraries, most recently added first. A test can change them, as if someone
    /// added something.
    public var items: [Item] {
        get { itemStore.withLock { $0 } }
        set { itemStore.withLock { $0 = newValue } }
    }
    /// What it sends for any image it has. A real PNG unless a test says otherwise.
    public let imageData: Data

    private let recorded = Mutex<[URLRequest]>([])
    private let itemStore: Mutex<[Item]>
    /// Access tokens the server currently accepts, and whose they are.
    private let sessions = Mutex<[String: Account]>([:])

    public init(
        url: URL = MockJellyfinServer.uniqueURL(),
        name: String = "Living Room",
        version: String = "10.11.2",
        productName: String = "Jellyfin Server",
        accounts: [Account] = [Account(name: "alex", password: "hunter2")],
        loginDisclaimer: String? = nil,
        splashscreenEnabled: Bool = false,
        hostsWebClient: Bool = true,
        items: [Item] = [],
        imageData: Data = MockJellyfinServer.samplePNG,
        behavior: Behavior = .jellyfin
    ) {
        self.url = url
        self.id = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        self.name = name
        self.version = version
        self.productName = productName
        self.accounts = accounts
        self.loginDisclaimer = loginDisclaimer
        self.splashscreenEnabled = splashscreenEnabled
        self.hostsWebClient = hostsWebClient
        itemStore = Mutex(items)
        self.imageData = imageData
        self.behavior = behavior
        Self.registry.withLock { $0[Self.origin(of: url)] = WeakServer(server: self) }
    }

    deinit {
        let origin = Self.origin(of: url)
        Self.registry.withLock { _ = $0.removeValue(forKey: origin) }
    }

    /// A URL on a host no other mock uses, HTTPS unless told otherwise.
    public static func uniqueURL(scheme: String = "https", port: Int? = nil) -> URL {
        let host = "mock-\(UUID().uuidString.lowercased()).jellyfin.test"
        return URL(string: "\(scheme)://\(host)\(port.map { ":\($0)" } ?? "")")!
    }

    /// Every request the server received, in order.
    public var requests: [URLRequest] { recorded.withLock { $0 } }

    /// Access tokens the server currently accepts.
    public var activeTokens: Set<String> { sessions.withLock { Set($0.keys) } }

    /// Revokes every session, like removing the device in the Jellyfin dashboard.
    public func revokeAllSessions() {
        sessions.withLock { $0.removeAll() }
    }

    /// Hand this to the client under test so its requests reach mock servers.
    public static var sessionConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return configuration
    }

    // MARK: Responses

    struct Response {
        var status: Int
        var json: Any?
        var html: String?
        var image: Data?
    }

    fileprivate func respond(to request: URLRequest) throws(URLError) -> Response {
        recorded.withLock { $0.append(request) }

        switch behavior {
        case .offline:
            throw URLError(.cannotConnectToHost)
        case .otherWebServer(let status):
            return Response(status: status, html: "<html><body>Router login</body></html>")
        case .failing(let status):
            return Response(status: status, json: ["Message": "Internal server error"])
        case .jellyfin:
            break
        }

        switch (request.httpMethod ?? "GET", request.url?.path ?? "") {
        case ("GET", "/System/Info/Public"):
            return Response(status: 200, json: publicSystemInfo)
        case ("GET", "/Users/Public"):
            return Response(status: 200, json: accounts.filter { !$0.isHidden }.map(userJSON))
        case ("GET", "/web/manifest.json") where hostsWebClient:
            // As Jellyfin's web client lists them, smallest first.
            return Response(status: 200, json: ["icons": [
                ["src": "favicons/touchicon72.png", "sizes": "72x72", "type": "image/png"],
                ["src": "favicons/touchicon512.png", "sizes": "512x512", "type": "image/png"],
                ["src": "favicons/touchicon144.png", "sizes": "144x144", "type": "image/png"],
            ]])
        case ("GET", "/Branding/Configuration"):
            return Response(status: 200, json: [
                "LoginDisclaimer": loginDisclaimer ?? "",
                "CustomCss": "",
                "SplashscreenEnabled": splashscreenEnabled,
            ])
        case ("POST", "/Users/AuthenticateByName"):
            return authenticate(request)
        case ("GET", "/Users/Me"):
            guard let account = account(for: request) else { return Response(status: 401) }
            return Response(status: 200, json: userJSON(account))
        case ("POST", "/Sessions/Logout"):
            guard let token = token(in: request), account(for: request) != nil else { return Response(status: 401) }
            sessions.withLock { _ = $0.removeValue(forKey: token) }
            return Response(status: 204)
        case ("GET", "/Items/Latest"):
            guard account(for: request) != nil else { return Response(status: 401) }
            let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems
            let limit = query?.first { $0.name == "limit" }?.value.flatMap(Int.init)
            return Response(status: 200, json: items.prefix(limit ?? items.count).map(itemJSON))
        case ("GET", let path) where path.hasPrefix("/Items/"):
            // Images need no sign-in, as on a real server.
            return hasImage(at: path) ? Response(status: 200, image: imageData) : Response(status: 404)
        default:
            return Response(status: 404)
        }
    }

    private func itemJSON(_ item: Item) -> [String: Any] {
        var json: [String: Any] = [
            "Id": item.id,
            "Name": item.name,
            "Type": item.type,
            "ServerId": id,
            "ImageTags": item.imageTags,
            "BackdropImageTags": item.backdropTags,
        ]
        json["PrimaryImageAspectRatio"] = item.primaryImageAspectRatio
        return json
    }

    /// Whether `/Items/{id}/Images/{type}` or `/Items/{id}/Images/Backdrop/{index}` is an image the
    /// server has.
    private func hasImage(at path: String) -> Bool {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 4, parts[2] == "Images", let item = items.first(where: { $0.id == parts[1] }) else {
            return false
        }
        if parts[3] == "Backdrop" {
            let index = parts.count > 4 ? Int(parts[4]) ?? -1 : 0
            return item.backdropTags.indices.contains(index)
        }
        return item.imageTags[parts[3]] != nil
    }

    private var publicSystemInfo: [String: Any] {
        [
            "LocalAddress": url.absoluteString,
            "ServerName": name,
            "Version": version,
            "ProductName": productName,
            "OperatingSystem": "",
            "Id": id,
            "StartupWizardCompleted": true,
        ]
    }

    private func authenticate(_ request: URLRequest) -> Response {
        guard
            let body = request.bodyData,
            let credentials = try? JSONSerialization.jsonObject(with: body) as? [String: String],
            let account = accounts.first(where: {
                $0.name.caseInsensitiveCompare(credentials["Username"] ?? "") == .orderedSame
            }),
            account.password == credentials["Pw"] else {
            return Response(status: 401)
        }
        let token = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        sessions.withLock { $0[token] = account }
        return Response(status: 200, json: [
            "User": userJSON(account),
            "AccessToken": token,
            "ServerId": id,
        ])
    }

    private func userJSON(_ account: Account) -> [String: Any] {
        var json: [String: Any] = [
            "Name": account.name,
            "ServerId": id,
            "Id": account.id,
            "HasPassword": !account.password.isEmpty,
            "HasConfiguredPassword": !account.password.isEmpty,
        ]
        json["PrimaryImageTag"] = account.imageTag
        return json
    }

    /// The account behind the request's access token, if the server still accepts it.
    private func account(for request: URLRequest) -> Account? {
        guard let token = token(in: request) else { return nil }
        return sessions.withLock { $0[token] }
    }

    /// Reads `Token=…` from the `Authorization: MediaBrowser …` header.
    private func token(in request: URLRequest) -> String? {
        guard let header = request.value(forHTTPHeaderField: "Authorization"), header.hasPrefix("MediaBrowser ") else {
            return nil
        }
        return header.dropFirst("MediaBrowser ".count)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("Token=") }
            .map { String($0.dropFirst("Token=".count)) }
    }

    // MARK: Routing

    /// Weak, so a server unregisters itself when the test that made it is done.
    fileprivate struct WeakServer: Sendable {
        weak var server: MockJellyfinServer?
    }

    /// Servers by the scheme, host and port they listen on.
    fileprivate static let registry = Mutex<[String: WeakServer]>([:])

    fileprivate static func origin(of url: URL) -> String {
        "\(url.scheme ?? "")://\(url.host ?? ""):\(url.port.map(String.init) ?? "")"
    }
}

/// Delivers each request to the `MockJellyfinServer` listening at its scheme, host and port. Nothing
/// listening there fails like a closed port.
private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url,
            let server = MockJellyfinServer.registry.withLock({ $0[MockJellyfinServer.origin(of: url)]?.server }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        do {
            let response = try server.respond(to: request)
            let body: Data
            let contentType: String
            if let image = response.image {
                body = image
                contentType = "image/png"
            } else if let json = response.json {
                body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
                contentType = "application/json"
            } else {
                body = Data((response.html ?? "").utf8)
                contentType = "text/html"
            }
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: response.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": contentType]
            )!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

extension URLRequest {
    /// URLSession hands protocols the body as a stream, not as `httpBody`.
    var bodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
