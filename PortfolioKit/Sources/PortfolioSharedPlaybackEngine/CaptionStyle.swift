import CoreText
import Foundation
import MediaAccessibility
import SwiftUI

/// How the user has subtitles drawn (Settings › Accessibility › Subtitles and Captioning), read from
/// MediaAccessibility as AVKit reads it: the system's own values for whatever they haven't set.
public struct CaptionStyle: Hashable, Sendable {
    /// How text's edges are drawn.
    public enum Edge: Hashable, Sendable {
        case none, raised, depressed, outline, dropShadow
    }

    /// The font's name, or nil for the system font.
    public var fontName: String?
    /// How much bigger than usual text is drawn.
    public var sizeScale: Double = 1
    public var textColor: Color = .white
    /// Behind each line.
    public var background: Color = .clear
    /// Behind all the lines.
    public var window: Color = .clear
    public var windowCornerRadius: CGFloat = 0
    public var edge: Edge = .none

    public init(
        fontName: String? = nil,
        sizeScale: Double = 1,
        textColor: Color = .white,
        background: Color = .clear,
        window: Color = .clear,
        windowCornerRadius: CGFloat = 0,
        edge: Edge = .none
    ) {
        self.fontName = fontName
        self.sizeScale = sizeScale
        self.textColor = textColor
        self.background = background
        self.window = window
        self.windowCornerRadius = windowCornerRadius
        self.edge = edge
    }

    /// Subtitles as the file has them, for Style's Original: white where the file gives no color, in the
    /// system font, with a soft shadow and nothing behind them.
    public static let original = CaptionStyle(edge: .dropShadow)

    /// The style subtitles have now.
    public static func current() -> CaptionStyle {
        let domain = MACaptionAppearanceDomain.user
        let font = MACaptionAppearanceCopyFontDescriptorForStyle(domain, nil, .default).takeRetainedValue()
        return CaptionStyle(
            fontName: CTFontDescriptorCopyAttribute(font, kCTFontNameAttribute) as? String,
            sizeScale: Double(MACaptionAppearanceGetRelativeCharacterSize(domain, nil)),
            textColor: color(MACaptionAppearanceCopyForegroundColor(domain, nil).takeRetainedValue(), MACaptionAppearanceGetForegroundOpacity(domain, nil)),
            background: color(MACaptionAppearanceCopyBackgroundColor(domain, nil).takeRetainedValue(), MACaptionAppearanceGetBackgroundOpacity(domain, nil)),
            window: color(MACaptionAppearanceCopyWindowColor(domain, nil).takeRetainedValue(), MACaptionAppearanceGetWindowOpacity(domain, nil)),
            windowCornerRadius: MACaptionAppearanceGetWindowRoundedCornerRadius(domain, nil),
            edge: Edge(MACaptionAppearanceGetTextEdgeStyle(domain, nil))
        )
    }

    /// The style subtitles would have with the system's caption style `id` chosen, without choosing it.
    public static func ofSystemStyle(_ id: String) -> CaptionStyle {
        nonisolated(unsafe) var style = CaptionStyle()
        MACaptionAppearanceExecuteBlockForProfileID(id as CFString) { style = current() }
        return style
    }

    /// Posted when the user's caption style changes, here or in Settings.
    public static let didChange = Notification.Name(kMACaptionAppearanceSettingsChangedNotification as String)

    private static func color(_ color: CGColor, _ opacity: CGFloat) -> Color {
        Color(cgColor: color).opacity(opacity)
    }
}

private extension CaptionStyle.Edge {
    init(_ style: MACaptionAppearanceTextEdgeStyle) {
        self = switch style {
        case .raised: .raised
        case .depressed: .depressed
        case .uniform: .outline
        case .dropShadow: .dropShadow
        default: .none
        }
    }
}

/// One of the system's caption styles, such as Classic or Large Text.
public struct CaptionStyleOption: Identifiable, Hashable, Sendable {
    /// The system's name for it, not shown.
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// The system's caption styles, and which the user has chosen: choosing one chooses it for every app,
/// as the system player's Style menu does.
public struct CaptionStyles: Sendable {
    /// The styles to choose from, in the system's order.
    public var options: @Sendable () -> [CaptionStyleOption]
    /// The one chosen.
    public var chosen: @Sendable () -> CaptionStyleOption.ID?
    public var choose: @Sendable (CaptionStyleOption.ID) -> Void
    /// How subtitles look in a style, without choosing it.
    public var appearance: @Sendable (CaptionStyleOption.ID) -> CaptionStyle

    public init(
        options: @escaping @Sendable () -> [CaptionStyleOption],
        chosen: @escaping @Sendable () -> CaptionStyleOption.ID?,
        choose: @escaping @Sendable (CaptionStyleOption.ID) -> Void,
        appearance: @escaping @Sendable (CaptionStyleOption.ID) -> CaptionStyle
    ) {
        self.options = options
        self.chosen = chosen
        self.choose = choose
        self.appearance = appearance
    }

    /// MediaAccessibility's.
    public static let system = CaptionStyles(
        options: {
            let ids = MACaptionAppearanceCopyProfileIDs() as? [String] ?? []
            return ids.map { CaptionStyleOption(id: $0, name: MACaptionAppearanceCopyProfileName($0 as CFString) as String) }
        },
        chosen: { MACaptionAppearanceCopyActiveProfileID() as String },
        choose: { MACaptionAppearanceSetActiveProfileID($0 as CFString) },
        appearance: CaptionStyle.ofSystemStyle
    )
}
