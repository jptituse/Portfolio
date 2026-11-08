import Foundation
import Synchronization

/// An in-process stand-in for a Jellyfin server, for unit tests.
///
/// It answers the endpoints the client uses with responses shaped like a real server's, checks
/// credentials against its accounts, and records every request. Requests never leave the process:
/// `MockJellyfinServer.sessionConfiguration` routes them to the server registered for their host,
/// and each instance gets its own host, so tests can run in parallel.
final class MockJellyfinServer: Sendable {
    struct Account: Sendable {
        var name: String
        var password: String
        var id = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
    }

    /// How the server responds.
    enum Behavior: Sendable {
        /// Behaves like a working Jellyfin server.
        case jellyfin
        /// Nothing is listening: every request fails to connect.
        case offline
        /// Some other web server: every request gets this status and an HTML page.
        case otherWebServer(status: Int)
        /// A Jellyfin server that fails every request with this status.
        case failing(status: Int)
    }

    let url: URL
    let id: String
    let name: String
    let version: String
    let productName: String
    let accounts: [Account]
    let behavior: Behavior

    private let recorded = Mutex<[URLRequest]>([])

    init(
        name: String = "Living Room",
        version: String = "10.11.2",
        productName: String = "Jellyfin Server",
        accounts: [Account] = [Account(name: "alex", password: "hunter2")],
        behavior: Behavior = .jellyfin
    ) {
        self.url = URL(string: "https://mock-\(UUID().uuidString.lowercased()).jellyfin.test")!
        self.id = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        self.name = name
        self.version = version
        self.productName = productName
        self.accounts = accounts
        self.behavior = behavior
        Self.registry.withLock { $0[url.host!] = WeakServer(server: self) }
    }

    deinit {
        let host = url.host!
        Self.registry.withLock { _ = $0.removeValue(forKey: host) }
    }

    /// Every request the server received, in order.
    var requests: [URLRequest] { recorded.withLock { $0 } }

    /// Hand this to the client under test so its requests reach mock servers.
    static var sessionConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return configuration
    }

    // MARK: Responses

    struct Response {
        var status: Int
        var json: Any?
        var html: String?
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
        case ("POST", "/Users/AuthenticateByName"):
            return authenticate(request)
        default:
            return Response(status: 404)
        }
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
            account.password == credentials["Pw"]
        else {
            return Response(status: 401)
        }
        let user: [String: Any] = [
            "Name": account.name,
            "ServerId": id,
            "Id": account.id,
            "HasPassword": !account.password.isEmpty,
            "HasConfiguredPassword": !account.password.isEmpty,
        ]
        return Response(status: 200, json: [
            "User": user,
            "AccessToken": UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: ""),
            "ServerId": id,
        ])
    }

    // MARK: Routing

    /// Weak, so a server unregisters itself when the test that made it is done.
    fileprivate struct WeakServer: Sendable {
        weak var server: MockJellyfinServer?
    }

    fileprivate static let registry = Mutex<[String: WeakServer]>([:])
}

/// Delivers each request to the `MockJellyfinServer` registered for its host.
private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let host = request.url?.host,
            let server = MockJellyfinServer.registry.withLock({ $0[host]?.server })
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        do {
            let response = try server.respond(to: request)
            let body: Data
            let contentType: String
            if let json = response.json {
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
