import SwiftUI

/// Lines of subtitle text drawn in a caption style, centered one under another: each on its background,
/// all on the window, with the edges the style asks for.
public struct CaptionTextView: View {
    let lines: [AttributedString]
    let style: CaptionStyle
    /// The font's size before the style scales it.
    let size: CGFloat

    public init(lines: [AttributedString], style: CaptionStyle, size: CGFloat) {
        self.lines = lines
        self.style = style
        self.size = size
    }

    public var body: some View {
        let size = size * style.sizeScale
        VStack(spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(font(size: size))
                    .foregroundStyle(style.textColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, size * Metrics.backgroundInset)
                    .background(style.background)
                    .modifier(Edge(edge: style.edge, size: size))
            }
        }
        .padding(size * Metrics.windowInset)
        .background(style.window, in: .rect(cornerRadius: style.windowCornerRadius))
    }

    private func font(size: CGFloat) -> Font {
        guard let name = style.fontName else { return .system(size: size) }
        return .custom(name, fixedSize: size)
    }
}

extension CaptionTextView {
    /// Draws text's edges as the style asks: raised, depressed, outlined or with a drop shadow.
    struct Edge: ViewModifier {
        let edge: CaptionStyle.Edge
        let size: CGFloat

        func body(content: Content) -> some View {
            let width = max(1, size / 24)
            switch edge {
            case .raised:
                content.shadow(color: .black, radius: 0, x: -width, y: -width)
            case .depressed:
                content.shadow(color: .black, radius: 0, x: width, y: width)
            case .outline:
                content
                    .shadow(color: .black, radius: 0, x: width, y: 0)
                    .shadow(color: .black, radius: 0, x: -width, y: 0)
                    .shadow(color: .black, radius: 0, x: 0, y: width)
                    .shadow(color: .black, radius: 0, x: 0, y: -width)
            case .dropShadow:
                content.shadow(color: .black.opacity(0.8), radius: width, x: width, y: width)
            case .none:
                content
            }
        }
    }

    struct Metrics {
        /// The background's room either side of each line, and the window's around them, in font sizes.
        static let backgroundInset: CGFloat = 0.25
        static let windowInset: CGFloat = 0.25
    }
}
