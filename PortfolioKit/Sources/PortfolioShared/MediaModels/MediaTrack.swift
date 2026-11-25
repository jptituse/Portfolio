import Foundation

/// One of the audio or subtitle tracks of what's playing, as its server lists them.
public struct MediaTrack: Identifiable, Hashable, Sendable {
    /// How the track reaches the player.
    public enum Delivery: Hashable, Sendable {
        /// In the media the player gets, such as the file it plays as it is.
        case inStream
        /// In a file of its own, which the player fetches: subtitles beside the media, or ones the server
        /// takes out of it.
        case file(URL)
        /// Only in a stream the server makes with it: subtitles it draws into the picture, or audio from a
        /// file of its own.
        case transcoded
    }

    /// Its number among the version's streams, as its server numbers them.
    public let id: Int
    /// What it's called, such as "English - Dolby Digital+ - 5.1 - Default".
    public let title: String
    /// Its language, as a language code, if known.
    public let language: String?
    /// Whether the media marks it as the one to use.
    public let isDefault: Bool
    /// Subtitles meant to show even with subtitles off, such as for signs and foreign dialogue.
    public let isForced: Bool
    /// Subtitles drawn as text, rather than as pictures, as a Blu-ray's or DVD's are.
    public let isText: Bool
    public let delivery: Delivery

    public init(
        id: Int,
        title: String,
        language: String? = nil,
        isDefault: Bool = false,
        isForced: Bool = false,
        isText: Bool = true,
        delivery: Delivery = .inStream
    ) {
        self.id = id
        self.title = title
        self.language = language
        self.isDefault = isDefault
        self.isForced = isForced
        self.isText = isText
        self.delivery = delivery
    }
}
