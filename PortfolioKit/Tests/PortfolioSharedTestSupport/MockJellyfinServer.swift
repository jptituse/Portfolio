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
        /// The languages it prefers to play audio and subtitles in, by ISO 639-2 code.
        public var audioLanguage: String?
        public var subtitleLanguage: String?
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
        /// The library it's in, if any.
        public var libraryID: String?
        public var genres: [String]
        public var runtimeMinutes: Int?
        /// How far the user has watched it, in minutes. Anything above zero puts it among the items to
        /// resume.
        public var watchedMinutes = 0
        /// When the user last started playing it.
        public var lastPlayed: Date?
        /// Whether it's the next episode of a show the user is watching.
        public var isNextUp = false
        public var seriesName: String?
        public var seriesID: String?
        public var seasonNumber: Int?
        public var episodeNumber: Int?
        /// Whether the server would send its default version as it is to a client that plays it.
        public var isDirectlyPlayable = true
        /// Whether the server would make a stream of it for a client, when it can't send it as it is.
        public var isTranscodable = true
        /// Its default version's streams, numbered as Jellyfin numbers them: files beside it first.
        public var streams = Stream.samples
        /// The audio stream the server picks for the user, else the one marked default.
        public var defaultAudioStream: Int?
        /// The subtitles the server picks for the user, if any.
        public var defaultSubtitleStream: Int?
        /// Its default version's bitrate, in bits per second.
        public var bitrate = 20_000_000
        public var id = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")

        public init(
            name: String,
            type: String = "Movie",
            imageTags: [String: String] = [:],
            backdropTags: [String] = [],
            primaryImageAspectRatio: Double? = nil,
            libraryID: String? = nil,
            genres: [String] = []
        ) {
            self.name = name
            self.type = type
            self.imageTags = imageTags
            self.backdropTags = backdropTags
            self.primaryImageAspectRatio = primaryImageAspectRatio
            self.libraryID = libraryID
            self.genres = genres
        }
    }

    /// One of an item's streams.
    public struct Stream: Sendable {
        public enum Kind: String, Sendable {
            case video = "Video"
            case audio = "Audio"
            case subtitle = "Subtitle"
        }

        public var index: Int
        public var kind: Kind
        public var title: String
        public var language: String?
        public var codec: String
        public var isDefault: Bool
        /// In a file of its own, beside the media.
        public var isExternal: Bool
        /// Subtitles drawn as text, rather than pictures.
        public var isText: Bool

        public init(index: Int, kind: Kind, title: String, language: String? = nil, codec: String, isDefault: Bool = false, isExternal: Bool = false, isText: Bool = true) {
            self.index = index
            self.kind = kind
            self.title = title
            self.language = language
            self.codec = codec
            self.isDefault = isDefault
            self.isExternal = isExternal
            self.isText = isText
        }

        /// A film's streams: subtitles in files of their own (as text, and as pictures), then the file's
        /// own video, two audio tracks and two subtitle tracks (as text, and as pictures).
        public static let samples = [
            Stream(index: 0, kind: .subtitle, title: "English - SDH - SRT - External", language: "eng", codec: "srt", isExternal: true),
            Stream(index: 1, kind: .subtitle, title: "French - PGSSUB - External", language: "fre", codec: "PGSSUB", isExternal: true, isText: false),
            Stream(index: 2, kind: .video, title: "4K HEVC Dolby Vision", codec: "hevc"),
            Stream(index: 3, kind: .audio, title: "English - Dolby Digital+ - 5.1 - Default", language: "eng", codec: "eac3", isDefault: true),
            Stream(index: 4, kind: .audio, title: "Spanish - AAC - Stereo", language: "spa", codec: "aac"),
            Stream(index: 5, kind: .subtitle, title: "English - SUBRIP", language: "eng", codec: "subrip"),
            Stream(index: 6, kind: .subtitle, title: "Spanish - PGSSUB", language: "spa", codec: "PGSSUB", isText: false),
        ]
    }

    /// One of the user's libraries.
    public struct Library: Sendable {
        public var name: String
        /// The Jellyfin collection type, such as `movies` or `tvshows`, or nil for a mixed library.
        public var collectionType: String?
        public var id = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")

        public init(name: String, collectionType: String?) {
            self.name = name
            self.collectionType = collectionType
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
    /// The user's libraries, in order.
    public let libraries: [Library]
    /// The items in its libraries, most recently added first. A test can change them, as if someone
    /// added something.
    public var items: [Item] {
        get { itemStore.withLock { $0 } }
        set { itemStore.withLock { $0 = newValue } }
    }
    /// What it sends for any image it has. A real PNG unless a test says otherwise.
    public let imageData: Data
    /// The libraries the user has left out of their latest items.
    public let librariesLeftOutOfLatest: [String]

    private let recorded = Mutex<[URLRequest]>([])
    private let playbackInfoBodies = Mutex<[Data]>([])
    private let reports = Mutex<[PlaybackReport]>([])
    private let playSessions = Mutex(0)
    private let stoppedSessions = Mutex<[String]>([])
    private let itemStore: Mutex<[Item]>
    /// Names and picture tags accounts were given, by account ID: a removed picture's tag is nil.
    private let renamed = Mutex<[String: String]>([:])
    private let pictures = Mutex<[String: String?]>([:])
    /// The pictures sent, as the server received them: base64-encoded.
    public var uploadedPictures: [Data] { uploads.withLock { $0 } }
    private let uploads = Mutex<[Data]>([])
    /// The users sent to be saved, as JSON.
    public var savedUsers: [Data] { userUpdates.withLock { $0 } }
    private let userUpdates = Mutex<[Data]>([])
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
        libraries: [Library] = [],
        items: [Item] = [],
        librariesLeftOutOfLatest: [String] = [],
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
        self.libraries = libraries
        itemStore = Mutex(items)
        self.librariesLeftOutOfLatest = librariesLeftOutOfLatest
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

    /// The bodies of the `PlaybackInfo` requests it got, in order: what each client said it can play.
    public var playbackInfoRequests: [Data] { playbackInfoBodies.withLock { $0 } }

    /// A client telling it playback started, where it is, or that it stopped.
    public struct PlaybackReport: Sendable {
        public enum Kind: Sendable { case started, progress, stopped }
        public let kind: Kind
        /// The report, as JSON.
        public let body: Data
    }

    /// The playback reports it got, in order.
    public var playbackReports: [PlaybackReport] { reports.withLock { $0 } }

    /// The play sessions whose streams a client asked it to stop making, in order.
    public var stoppedTranscodes: [String] { stoppedSessions.withLock { $0 } }

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
        case ("POST", "/Users"):
            guard let account = account(for: request) else { return Response(status: 401) }
            guard let body = request.bodyData, let user = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                let name = user["Name"] as? String else {
                return Response(status: 400)
            }
            renamed.withLock { $0[account.id] = name }
            userUpdates.withLock { $0.append(body) }
            return Response(status: 204)
        case ("POST", "/UserImage"):
            guard let account = account(for: request) else { return Response(status: 401) }
            uploads.withLock { $0.append(request.bodyData ?? Data()) }
            pictures.withLock { $0[account.id] = UUID().uuidString.prefix(8).lowercased() }
            return Response(status: 204)
        case ("DELETE", "/UserImage"):
            guard let account = account(for: request) else { return Response(status: 401) }
            pictures.withLock { $0[account.id] = .some(nil) }
            return Response(status: 204)
        case ("GET", "/Localization/Cultures"):
            guard account(for: request) != nil else { return Response(status: 401) }
            return Response(status: 200, json: Self.cultures)
        case ("GET", "/System/Ping"):
            return Response(status: 200, html: productName)
        case ("GET", "/Playback/BitrateTest"):
            guard account(for: request) != nil else { return Response(status: 401) }
            let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems
            let size = query?.first { $0.name == "size" }?.value.flatMap(Int.init) ?? 102_400
            return Response(status: 200, image: Data(count: size))
        case ("POST", "/Sessions/Logout"):
            guard let token = token(in: request), account(for: request) != nil else { return Response(status: 401) }
            sessions.withLock { _ = $0.removeValue(forKey: token) }
            return Response(status: 204)
        case ("GET", "/Items/Latest"):
            guard account(for: request) != nil else { return Response(status: 401) }
            let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems
            let limit = query?.first { $0.name == "limit" }?.value.flatMap(Int.init)
            let parent = query?.first { $0.name == "parentId" }?.value
            let latest = items.filter { item in
                parent.map { item.libraryID == $0 } ?? !librariesLeftOutOfLatest.contains { item.libraryID == $0 }
            }
            return Response(status: 200, json: latest.prefix(limit ?? latest.count).map(itemJSON))
        case ("GET", "/UserItems/Resume"):
            guard account(for: request) != nil else { return Response(status: 401) }
            let resume = items.filter { $0.watchedMinutes > 0 }
            return Response(status: 200, json: ["Items": resume.map(itemJSON), "TotalRecordCount": resume.count])
        case ("GET", "/Shows/NextUp"):
            guard account(for: request) != nil else { return Response(status: 401) }
            let nextUp = items.filter(\.isNextUp)
            return Response(status: 200, json: ["Items": nextUp.map(itemJSON), "TotalRecordCount": nextUp.count])
        case ("GET", "/UserViews"):
            guard account(for: request) != nil else { return Response(status: 401) }
            return Response(status: 200, json: ["Items": libraries.map(libraryJSON), "TotalRecordCount": libraries.count])
        case ("GET", "/Items"):
            guard account(for: request) != nil else { return Response(status: 401) }
            return Response(status: 200, json: itemsResponse(for: request))
        case ("GET", "/Genres"):
            guard account(for: request) != nil else { return Response(status: 401) }
            let names = Set(matchingItems(for: request).flatMap(\.genres)).sorted()
            return Response(status: 200, json: ["Items": names.map { ["Id": Self.genreID($0), "Name": $0] }, "TotalRecordCount": names.count])
        case ("POST", "/Sessions/Playing"), ("POST", "/Sessions/Playing/Progress"), ("POST", "/Sessions/Playing/Stopped"):
            guard account(for: request) != nil else { return Response(status: 401) }
            let kind: PlaybackReport.Kind = switch request.url?.path {
            case "/Sessions/Playing": .started
            case "/Sessions/Playing/Progress": .progress
            default: .stopped
            }
            reports.withLock { $0.append(PlaybackReport(kind: kind, body: request.bodyData ?? Data())) }
            return Response(status: 204)
        case ("GET", let path) where path.hasPrefix("/UserItems/") && path.hasSuffix("/UserData"):
            guard account(for: request) != nil else { return Response(status: 401) }
            let itemID = path.split(separator: "/")[1]
            guard let item = items.first(where: { $0.id == itemID }) else { return Response(status: 404) }
            return Response(status: 200, json: userDataJSON(item))
        case ("POST", let path) where path.hasPrefix("/Items/") && path.hasSuffix("/PlaybackInfo"):
            guard account(for: request) != nil else { return Response(status: 401) }
            if let body = request.bodyData { playbackInfoBodies.withLock { $0.append(body) } }
            let itemID = path.split(separator: "/")[1]
            guard let item = items.first(where: { $0.id == itemID }) else { return Response(status: 404) }
            let body = request.bodyData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            return Response(status: 200, json: playbackInfo(for: item, asked: body, token: token(in: request) ?? ""))
        case ("DELETE", "/Videos/ActiveEncodings"):
            guard account(for: request) != nil else { return Response(status: 401) }
            let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems
            if let session = query?.first(where: { $0.name == "playSessionId" })?.value {
                stoppedSessions.withLock { $0.append(session) }
            }
            return Response(status: 204)
        case ("GET", let path) where path.hasPrefix("/Items/"):
            // Images need no sign-in, as on a real server.
            return hasImage(at: path) ? Response(status: 200, image: imageData) : Response(status: 404)
        default:
            return Response(status: 404)
        }
    }

    /// The item's versions, its default first, as `PlaybackInfo` lists them: its own, and another the
    /// app should never pick. Its own plays as it is if the item does, unless the client asks for less
    /// than its bitrate, or for audio or subtitles only a transcode carries (a file of its own, or
    /// subtitles drawn as pictures in a file of their own); otherwise it's a transcode. Each answer is a
    /// new play session.
    private func playbackInfo(for item: Item, asked body: [String: Any], token: String) -> [String: Any] {
        let playSession = "play-session-\(playSessions.withLock { count in count += 1; return count })"
        let audio = body["AudioStreamIndex"] as? Int
            ?? item.defaultAudioStream
            ?? item.streams.first { $0.kind == .audio && $0.isDefault }?.index
        let subtitles = body["SubtitleStreamIndex"] as? Int ?? item.defaultSubtitleStream ?? -1
        let maxBitrate = body["MaxStreamingBitrate"] as? Int ?? .max
        let chosen = item.streams.filter { $0.index == audio || $0.index == subtitles }
        let directPlay = item.isDirectlyPlayable && maxBitrate >= item.bitrate && !chosen.contains { $0.isExternal && (!$0.isText || $0.kind == .audio) }
        let streams: [[String: Any]] = item.streams.map { stream in
            var json: [String: Any] = [
                "Index": stream.index, "Type": stream.kind.rawValue, "DisplayTitle": stream.title, "Codec": stream.codec,
                "IsDefault": stream.isDefault, "IsExternal": stream.isExternal, "IsForced": false,
            ]
            json["Language"] = stream.language
            guard stream.kind == .subtitle else { return json }
            json["IsTextSubtitleStream"] = stream.isText
            if directPlay && !stream.isExternal {
                json["DeliveryMethod"] = "Embed"
            } else if stream.isText {
                json["DeliveryMethod"] = "External"
                json["DeliveryUrl"] = "/Videos/\(item.id)/\(item.id)/Subtitles/\(stream.index)/0/Stream.srt?ApiKey=\(token)"
            } else {
                json["DeliveryMethod"] = "Encode"
            }
            return json
        }
        var version: [String: Any] = [
            "Id": item.id, "Container": "mkv", "Protocol": "File", "SupportsDirectPlay": directPlay,
            "SupportsDirectStream": directPlay, "SupportsTranscoding": true, "MediaStreams": streams,
            "Bitrate": item.bitrate, "DefaultSubtitleStreamIndex": subtitles,
        ]
        version["DefaultAudioStreamIndex"] = audio
        if !directPlay && item.isTranscodable {
            let bitrate = min(maxBitrate, item.bitrate)
            version["TranscodingUrl"] = "/videos/\(item.id)/master.m3u8?MediaSourceId=\(item.id)&PlaySessionId=\(playSession)"
                + "&AudioStreamIndex=\(audio ?? -1)&SubtitleStreamIndex=\(subtitles)&VideoBitrate=\(bitrate)&ApiKey=\(token)"
            version["TranscodingSubProtocol"] = "hls"
            version["TranscodingContainer"] = "mp4"
        }
        let other: [String: Any] = [
            "Id": "\(item.id)-other", "Container": "mp4", "Protocol": "File", "SupportsDirectPlay": true,
            "SupportsDirectStream": true, "SupportsTranscoding": true,
        ]
        return ["MediaSources": [version, other], "PlaySessionId": playSession]
    }

    /// The play session the first `PlaybackInfo` answer names. Each after it names the next: "play-session-2",
    /// and so on.
    public static let playSessionID = "play-session-1"

    private func libraryJSON(_ library: Library) -> [String: Any] {
        var json: [String: Any] = ["Id": library.id, "Name": library.name, "Type": "CollectionFolder", "ServerId": id]
        json["CollectionType"] = library.collectionType
        return json
    }

    /// A genre's ID: its name, so tests can find it.
    public static func genreID(_ name: String) -> String {
        "genre-\(name)"
    }

    /// The items a `/Items` or `/Genres` request asks about: in its library (`ParentId`), of its types
    /// (`IncludeItemTypes`), in its genre (`GenreIds`).
    private func matchingItems(for request: URLRequest) -> [Item] {
        let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
        let parent = query.first { $0.name == "parentId" }?.value
        let types = query.filter { $0.name == "includeItemTypes" }.compactMap(\.value)
        let genres = query.filter { $0.name == "genreIds" }.compactMap(\.value)
        return items.filter { item in
            (parent == nil || item.libraryID == parent)
                && (types.isEmpty || types.contains(item.type))
                && (genres.isEmpty || item.genres.contains { genres.contains(Self.genreID($0)) })
        }
    }

    /// A page of `/Items`: sorted by name, or with `DateCreated` (or `DateLastContentAdded`) first, in
    /// the order items were added, most recent first.
    private func itemsResponse(for request: URLRequest) -> [String: Any] {
        let query = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
        var matching = matchingItems(for: request)
        let sortBy = query.first { $0.name == "sortBy" }?.value
        if sortBy == "SortName" {
            matching.sort { $0.name < $1.name }
        }
        let start = query.first { $0.name == "startIndex" }?.value.flatMap(Int.init) ?? 0
        let limit = query.first { $0.name == "limit" }?.value.flatMap(Int.init) ?? matching.count
        let page = matching.dropFirst(start).prefix(limit)
        return ["Items": page.map(itemJSON), "TotalRecordCount": matching.count, "StartIndex": start]
    }

    private func itemJSON(_ item: Item) -> [String: Any] {
        var json: [String: Any] = [
            "Id": item.id,
            "Name": item.name,
            "Type": item.type,
            "ServerId": id,
            "ImageTags": item.imageTags,
            "Genres": item.genres,
            "BackdropImageTags": item.backdropTags,
        ]
        json["PrimaryImageAspectRatio"] = item.primaryImageAspectRatio
        json["RunTimeTicks"] = item.runtimeMinutes.map { $0 * Self.ticksPerMinute }
        json["UserData"] = userDataJSON(item)
        json["SeriesName"] = item.seriesName
        json["SeriesId"] = item.seriesID
        json["ParentIndexNumber"] = item.seasonNumber
        json["IndexNumber"] = item.episodeNumber
        return json
    }

    private func userDataJSON(_ item: Item) -> [String: Any] {
        var json: [String: Any] = [
            "PlaybackPositionTicks": item.watchedMinutes * Self.ticksPerMinute,
            "Played": false,
            "Key": item.id,
            "ItemId": item.id,
        ]
        json["LastPlayedDate"] = item.lastPlayed.map { $0.formatted(.iso8601) }
        return json
    }

    /// Jellyfin measures time in ticks of 100 nanoseconds.
    static let ticksPerMinute = 600_000_000

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
            "Name": renamed.withLock { $0[account.id] } ?? account.name,
            "ServerId": id,
            "Id": account.id,
            "HasPassword": !account.password.isEmpty,
            "HasConfiguredPassword": !account.password.isEmpty,
        ]
        json["PrimaryImageTag"] = pictures.withLock { $0[account.id] } ?? account.imageTag
        var configuration: [String: Any] = ["LatestItemsExcludes": librariesLeftOutOfLatest]
        configuration["AudioLanguagePreference"] = account.audioLanguage
        configuration["SubtitleLanguagePreference"] = account.subtitleLanguage
        json["Configuration"] = configuration
        return json
    }

    /// The cultures the server knows, as Jellyfin lists them: unsorted, and some languages more than
    /// once, under another name.
    static var cultures: [[String: Any]] {
        [
            ["Name": "French", "DisplayName": "French", "TwoLetterISOLanguageName": "fr", "ThreeLetterISOLanguageName": "fre"],
            ["Name": "English", "DisplayName": "English", "TwoLetterISOLanguageName": "en", "ThreeLetterISOLanguageName": "eng"],
            ["Name": "English (United Kingdom)", "DisplayName": "English (United Kingdom)", "TwoLetterISOLanguageName": "en", "ThreeLetterISOLanguageName": "eng"],
            ["Name": "Spanish", "DisplayName": "Spanish", "TwoLetterISOLanguageName": "es", "ThreeLetterISOLanguageName": "spa"],
        ]
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
