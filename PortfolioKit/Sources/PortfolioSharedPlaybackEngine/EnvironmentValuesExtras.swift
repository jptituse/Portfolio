import SwiftUI

extension EnvironmentValues {
    /// How far up from the bottom of the picture's space something covers it, such as a player's
    /// controls, for an engine's subtitles to stay above.
    @Entry public var subtitlesBottomInset: CGFloat = 0
    /// Whether subtitles are drawn as the file has them (`CaptionStyle.original`, in the file's own
    /// colors), rather than in the user's caption style.
    @Entry public var drawsOriginalSubtitles = false
}
