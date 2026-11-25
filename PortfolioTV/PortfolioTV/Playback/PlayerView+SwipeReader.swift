import SwiftUI
import UIKit

extension PlayerView {
    /// Reads swipes on the Siri Remote's touch surface, which SwiftUI doesn't report, and moves the
    /// scrubbing needle (`ScrubNeedle`) with them while `scrubs`, as the system player does: each move
    /// by its translation and speed, then a coast once the finger lifts, until a new touch or `scrubs`
    /// turning off stops it. The remote's touches go to the focused view and the views around it, so it
    /// watches them from the window, while `reads`. A swipe up or down moves focus instead, to the
    /// player's menus, so only one across can start scrubbing.
    struct SwipeReader: UIViewRepresentable {
        /// Whether it reads swipes: while focus is on the screen, not the menus.
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

        func makeUIView(context: Context) -> ReaderView {
            ReaderView()
        }

        func updateUIView(_ view: ReaderView, context: Context) {
            view.onBegan = onBegan
            view.needle.onMoved = onMoved
            view.needle.onInteractingChanged = onInteractingChanged
            view.marker = marker
            view.reads = reads
            view.scrubs = scrubs
        }

        final class ReaderView: UIView {
            var onBegan: () -> Double? = { nil }
            var marker: () -> Double = { 0 }
            var reads = true
            var scrubs = false {
                didSet { if !scrubs { stopScrubbing() } }
            }
            let needle = ScrubNeedle()
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
                if newWindow == nil { stopScrubbing() }
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
                    guard let spot = onBegan(), !isPlaced else { return }
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
}
