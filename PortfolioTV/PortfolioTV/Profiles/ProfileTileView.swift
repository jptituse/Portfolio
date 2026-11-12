import SwiftUI

/// A tile in a picker: a big round picture that lifts when focused, a name, and a line under it.
/// Selecting it runs `action`. People get their avatar as the picture; "Add Server" and "Someone
/// Else" get a `ProfileSymbolView`.
struct ProfileTileView<Picture: View>: View {
    let name: String
    var detail: String?
    /// Shows a spinner over the picture, while the profile opens.
    var isBusy = false
    let action: () -> Void
    @ViewBuilder let picture: Picture

    var body: some View {
        Button(action: action) {
            TileLabel(name: name, detail: detail, isBusy: isBusy, picture: picture)
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityLabel(name)
    }
}

extension ProfileTileView {
    /// Draws the label as it is: the system styles would put a rounded rectangle around the round
    /// picture when it's focused. `TileLabel` lifts the picture itself.
    struct TileButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? Metrics.pressedScale : 1)
                .animation(Metrics.lift, value: configuration.isPressed)
        }
    }

    /// The picture, which lifts while the tile has focus, and the name and detail under it.
    struct TileLabel: View {
        let name: String
        let detail: String?
        let isBusy: Bool
        let picture: Picture

        @Environment(\.isFocused) private var isFocused

        var body: some View {
            VStack(spacing: Metrics.spacing) {
                picture
                    .frame(width: Metrics.pictureSize, height: Metrics.pictureSize)
                    .overlay {
                        if isBusy {
                            ProgressView()
                        }
                    }
                    .scaleEffect(isFocused ? Metrics.focusedScale : 1)
                    .shadow(color: .black.opacity(isFocused ? Metrics.shadowOpacity : 0), radius: Metrics.shadowRadius, y: Metrics.shadowOffset)
                VStack(spacing: Metrics.textSpacing) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(isFocused ? .primary : .secondary)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                .offset(y: isFocused ? Metrics.focusedTextOffset : 0)
            }
            .frame(width: Metrics.width)
            .animation(Metrics.lift, value: isFocused)
        }
    }

    struct Metrics {
        static var pictureSize: CGFloat { 220 }
        static var width: CGFloat { 300 }
        static var spacing: CGFloat { 28 }
        static var textSpacing: CGFloat { 6 }
        static var focusedScale: CGFloat { 1.12 }
        static var pressedScale: CGFloat { 0.96 }
        static var focusedTextOffset: CGFloat { 14 }
        static var shadowOpacity: Double { 0.45 }
        static var shadowRadius: CGFloat { 24 }
        static var shadowOffset: CGFloat { 18 }
        static var lift: Animation { .smooth(duration: 0.2) }
    }
}

#Preview {
    HStack {
        ProfileTileView(name: "Alex", detail: "Living Room") {} picture: {
            ProfileSymbolView(systemName: "person.fill")
        }
        ProfileTileView(name: "Add Server") {} picture: {
            ProfileSymbolView(systemName: "plus")
        }
    }
}
