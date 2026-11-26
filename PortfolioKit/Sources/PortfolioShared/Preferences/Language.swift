/// A language media can be in, to choose one to play audio or subtitles in.
public struct Language: Hashable, Sendable, Identifiable {
    /// Its ISO 639-2 code, such as "eng".
    public let code: String
    /// Its name, such as "English".
    public let name: String

    public var id: String { code }

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

/// The languages an account on a server prefers to play audio and subtitles in, by ISO 639-2 code, or
/// nil where it has no preference.
public struct LanguagePreferences: Hashable, Sendable {
    public let audio: String?
    public let subtitle: String?

    public init(audio: String? = nil, subtitle: String? = nil) {
        self.audio = audio
        self.subtitle = subtitle
    }
}
