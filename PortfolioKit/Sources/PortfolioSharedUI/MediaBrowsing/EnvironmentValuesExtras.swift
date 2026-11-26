import SwiftUI

extension EnvironmentValues {
    /// Whether to keep what happens in episodes the profile hasn't watched to itself: their stills are
    /// blurred and their descriptions hidden (Settings' Spoiler Protection).
    @Entry public var hidesSpoilers = false
}
