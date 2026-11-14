import SwiftUI

/// A button around a `MediaCardView`, drawn as it is. A poster lifts with the `.highlight` hover effect
/// on the whole card, and a platter shows focus by the darkening of the others. A `.borderless` button
/// lifts each image in its label on its own instead, with corners and a shadow of its own: on an Apple
/// TV, a backdrop drew its own corners inside its moving card, and a poster's corners grew the moment
/// focus came back to it after its card closed. The simulator showed neither.
struct MediaCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
