import PortfolioSharedUI
import SwiftUI
import UIKit

extension PlayerView {
    /// Reads what SwiftUI doesn't report of the Siri Remote, as the system player reads it.
    ///
    /// **Swipes** on its touch surface move the scrubbing needle (`ScrubNeedle`) while `scrubs`: each
    /// move by its translation and speed, then a coast once the finger lifts, until a new touch or
    /// `scrubs` turning off stops it. The remote's touches go to the focused view and the views around
    /// it, so it watches them from the window, while `reads`. A swipe up or down moves focus instead, to
    /// the player's menus, so only one across can start scrubbing.
    ///
    /// **Clicks and holds of Left and Right** (`ArrowPressRecognizer`), while `reads`. They're read on
    /// the player's own view, which the focused screen button's presses pass through, as AVKit reads
    /// them on its player's. SwiftUI's `onMoveCommand`, under #15, never heard a click on an Apple TV.
    struct RemoteReader: UIViewRepresentable {
        /// Whether it reads swipes and clicks: while focus is on the screen, not the menus.
        let reads: Bool
        let scrubs: Bool
        /// Where playback is, from 0 to 1, for the needle to catch on. It's read as a swipe puts the
        /// needle on the bar, as playback stays put while paused, so the player isn't drawn again as the
        /// media plays.
        let marker: () -> Double
        /// A swipe began: gives where the spot is, from 0 to 1, if it's scrubbing.
        let onBegan: () -> Double?
        /// The needle moved to a spot, from 0 to 1 along the bar.
        let onMoved: (_ fraction: Double) -> Void
        /// A finger is moving the needle, or it's moving by itself: the bar's taller then.
        let onInteractingChanged: (_ isInteracting: Bool) -> Void
        /// The bar stretches past an end, the needle pushed on there, or lets go (nil).
        let onRubberBand: (_ end: HorizontalEdge?) -> Void
        /// Left or Right, clicked and let go.
        let onClick: (PlayerViewModel.Direction) -> Void
        /// Left or Right, held down `ArrowPressRecognizer.holdDelay`.
        let onHold: (PlayerViewModel.Direction) -> Void

        func makeUIView(context: Context) -> ReaderView {
            ReaderView()
        }

        func updateUIView(_ view: ReaderView, context: Context) {
            view.onBegan = onBegan
            view.needle.onMoved = onMoved
            view.needle.onInteractingChanged = onInteractingChanged
            view.needle.onRubberBand = onRubberBand
            view.marker = marker
            view.reads = reads
            view.scrubs = scrubs
            view.arrows.onClick = onClick
            view.arrows.onHold = onHold
        }

        final class ReaderView: UIView {
            var onBegan: () -> Double? = { nil }
            var marker: () -> Double = { 0 }
            var reads = true {
                didSet { arrows.isEnabled = reads }
            }
            var scrubs = false {
                didSet { if !scrubs { stopScrubbing() } }
            }
            let needle = ScrubNeedle()
            let arrows = ArrowPressRecognizer()
            /// Whether the needle is on the bar, from the swipe that started scrubbing until it ends.
            private var isPlaced = false
            private lazy var recognizer: UIPanGestureRecognizer = {
                let recognizer = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
                recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
                recognizer.cancelsTouchesInView = false
                return recognizer
            }()

            init() {
                super.init(frame: .zero)
                isUserInteractionEnabled = false
            }

            required init?(coder: NSCoder) {
                fatalError("init(coder:) is not used")
            }

            override func willMove(toWindow newWindow: UIWindow?) {
                recognizer.view?.removeGestureRecognizer(recognizer)
                newWindow?.addGestureRecognizer(recognizer)
                arrows.view?.removeGestureRecognizer(arrows)
                if newWindow == nil { stopScrubbing() }
            }

            override func didMoveToWindow() {
                guard window != nil else { return }
                playerView?.addGestureRecognizer(arrows)
            }

            /// The player's own view, which the presses of the focused view inside it pass through: the
            /// first around this one that's a view controller's, whose next responder isn't the view
            /// it's in. (SwiftUI's hosting view hands on to a key press responder of its own, then its
            /// controller.)
            private var playerView: UIView? {
                sequence(first: self as UIView, next: \.superview).first { $0.next !== $0.superview }
            }

            private func stopScrubbing() {
                needle.stop()
                isPlaced = false
            }

            /// The swipe's moves, in the window's points, as the system's controls read them in their
            /// full-screen view's: how far since the last one, and how fast.
            @objc private func panned(_ recognizer: UIPanGestureRecognizer) {
                guard let window else { return }
                let velocity = recognizer.velocity(in: window)
                switch recognizer.state {
                case .began:
                    guard reads else { return }
                    recognizer.setTranslation(.zero, in: window)
                    needle.touchBegan()
                    // Up or down moves focus, unless the needle's already on the bar.
                    guard isPlaced || abs(velocity.x) >= abs(velocity.y) else { return }
                    guard let spot = onBegan() else { return }
                    // Placed where the spot is, unless it's still moving: since the last swipe, a click,
                    // or the needle moving by itself, may have moved the spot.
                    guard !isPlaced || !needle.isInteracting else { return }
                    let barWidth = window.bounds.width - 2 * PlayerControlsView.Metrics.sideInset
                    needle.marker = marker()
                    needle.place(at: spot, barWidth: barWidth)
                    isPlaced = true
                case .changed:
                    guard isPlaced else { return }
                    // An up or down swipe, before the needle's left where playback is, isn't scrubbing.
                    guard abs(velocity.y) <= abs(velocity.x) || !needle.isAtMarker else { return }
                    let translation = recognizer.translation(in: window).x
                    recognizer.setTranslation(.zero, in: window)
                    needle.move(by: translation, speed: velocity.x)
                case .ended, .cancelled:
                    guard isPlaced else { return }
                    needle.lifted(speed: velocity.x)
                default:
                    break
                }
            }
        }
    }

    /// Left and Right pressed on the remote, as AVKit's `AVNonDigitizerTapRecognizer`s take them: let go
    /// within `holdDelay` it's a click; held that long it's a hold, at once, and letting go then does
    /// nothing more. One press at a time.
    final class ArrowPressRecognizer: UIGestureRecognizer {
        var onClick: (PlayerViewModel.Direction) -> Void = { _ in }
        var onHold: (PlayerViewModel.Direction) -> Void = { _ in }
        /// The press being read, and whether it's been held.
        private var press: UIPress?
        private var isHeld = false
        private var holding: Task<Void, Never>?

        init() {
            super.init(target: nil, action: nil)
            allowedPressTypes = [UIPress.PressType.leftArrow, .rightArrow].map { NSNumber(value: $0.rawValue) }
            allowedTouchTypes = []
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
            guard press == nil, let first = presses.first(where: { Self.direction(of: $0) != nil }),
                let direction = Self.direction(of: first) else {
                return
            }
            press = first
            holding = Task { [weak self] in
                try? await Task.sleep(for: Self.holdDelay)
                guard let self, !Task.isCancelled, press === first else { return }
                isHeld = true
                state = .began
                onHold(direction)
            }
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent) {
            guard let press, presses.contains(press), let direction = Self.direction(of: press) else { return }
            holding?.cancel()
            if !isHeld { onClick(direction) }
            state = .ended
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent) {
            guard let press, presses.contains(press) else { return }
            holding?.cancel()
            state = isHeld ? .cancelled : .failed
        }

        override func reset() {
            holding?.cancel()
            holding = nil
            press = nil
            isHeld = false
        }

        private static func direction(of press: UIPress) -> PlayerViewModel.Direction? {
            switch press.type {
            case .leftArrow: .back
            case .rightArrow: .forward
            default: nil
            }
        }

        /// How long a press is held before it's a hold: AVKit's (its hold recognizer's
        /// `minimumPressDuration`).
        static let holdDelay = Duration.milliseconds(500)
    }
}
