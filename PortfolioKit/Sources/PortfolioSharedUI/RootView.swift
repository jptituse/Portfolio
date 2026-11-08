import SwiftUI

/// The app's top-level view. Placeholder until the app shell lands (#6).
///
/// Screens, their view models and reusable views all live in this module, grouped into folders by
/// use case (generic building blocks go in `Components/`).
public struct RootView: View {
    public init() {}

    public var body: some View {
        ContentUnavailableView("Portfolio", systemImage: "play.tv")
    }
}
