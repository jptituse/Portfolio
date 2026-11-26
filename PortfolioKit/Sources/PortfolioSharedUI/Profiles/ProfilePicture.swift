import SwiftUI

/// One of the pictures someone can choose for their account, made here, since tvOS has no photo
/// picker: a white symbol on one color, without gradients, as the system's own pictures are. Chosen,
/// it's sent to the server as a PNG, so every Jellyfin client shows it.
public struct ProfilePicture: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    let symbol: String
    let color: Color

    /// The pictures to choose from.
    public static let all: [ProfilePicture] = [
        ProfilePicture(id: "popcorn", name: "Popcorn", symbol: "popcorn.fill", color: .red),
        ProfilePicture(id: "film", name: "Film", symbol: "film.fill", color: .indigo),
        ProfilePicture(id: "star", name: "Star", symbol: "star.fill", color: .yellow),
        ProfilePicture(id: "night", name: "Night", symbol: "moon.stars.fill", color: .blue),
        ProfilePicture(id: "leaf", name: "Leaf", symbol: "leaf.fill", color: .green),
        ProfilePicture(id: "flame", name: "Flame", symbol: "flame.fill", color: .orange),
        ProfilePicture(id: "bolt", name: "Bolt", symbol: "bolt.fill", color: .yellow),
        ProfilePicture(id: "heart", name: "Heart", symbol: "heart.fill", color: .pink),
        ProfilePicture(id: "paw", name: "Paw", symbol: "pawprint.fill", color: .brown),
        ProfilePicture(id: "music", name: "Music", symbol: "music.note", color: .purple),
        ProfilePicture(id: "games", name: "Games", symbol: "gamecontroller.fill", color: .teal),
        ProfilePicture(id: "globe", name: "Globe", symbol: "globe.americas.fill", color: .cyan),
    ]

    /// The picture as a square PNG `pixels` across, to send to the server.
    @MainActor
    public func pngData(pixels: CGFloat = 512) -> Data? {
        let renderer = ImageRenderer(content: ProfilePictureView(picture: self).frame(width: pixels, height: pixels))
        renderer.scale = 1
        #if canImport(UIKit)
        return renderer.uiImage?.pngData()
        #else
        return nil
        #endif
    }
}
