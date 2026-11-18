import SwiftUI

extension GeometryProxy {
    /// The size of the screen a full-screen view's in: its own size with its safe area added back. A
    /// view measured inside the safe area, even one asked to ignore it, can come up short of the screen,
    /// and artwork fetched at that size is scaled up to fill it.
    var screenSize: CGSize {
        CGSize(
            width: size.width + safeAreaInsets.leading + safeAreaInsets.trailing,
            height: size.height + safeAreaInsets.top + safeAreaInsets.bottom
        )
    }
}
