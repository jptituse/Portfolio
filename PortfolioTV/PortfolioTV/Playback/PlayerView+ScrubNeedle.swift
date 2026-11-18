import UIKit

extension PlayerView {
    /// The spot scrubbing picks, moved as the system player's transport bar moves its needle, on a bar
    /// `barWidth` points long. That's AVKit's private `AVNowPlayingTransportBar` (and
    /// `AVNowPlayingPlaybackControlsViewController`, which feeds it the remote's swipes), read from tvOS
    /// 27.2's AVKit; `Metrics` holds its numbers.
    ///
    /// It's UIKit Dynamics, as there. While the finger moves, the needle hangs from an anchor that moves
    /// by the swipe's translation, scaled by its speed (`gain(atSpeed:)`): slowly, a fiftieth of the
    /// finger's travel, for fine steps; fast, six times that. Lifting the finger faster than
    /// `Metrics.coastingSpeed` pushes the needle on, in proportion to the speed, and its resistance slows
    /// it to a stop within about a second. A new touch slows it at once. Moving slowly toward where
    /// playback is, it catches there, and stays until the swipe has moved on a little.
    ///
    /// The system's needle rubber-bands at the bar's ends; this one stops at them.
    final class ScrubNeedle: NSObject, UIDynamicAnimatorDelegate {
        /// Reports where the needle is, from 0 to 1 along the bar, each time it moves.
        var onMoved: (_ fraction: Double) -> Void = { _ in }
        /// Reports whether a finger is moving it, or it's still moving since one let go.
        var onInteractingChanged: (_ isInteracting: Bool) -> Void = { _ in }
        /// Where playback is, from 0 to 1, for the needle to catch on.
        var marker: Double = 0

        private(set) var isInteracting = false
        private(set) var barWidth: CGFloat = 0
        private let item = Item()
        private let animator = UIDynamicAnimator()
        private let body: UIDynamicItemBehavior
        private var attachment: UIAttachmentBehavior?
        private var push: UIPushBehavior?
        /// Whether a finger is moving the needle: from its first move until it lifts, or rests a second.
        private var isTracking = false
        /// Whether it's still moving since a finger let go, until UIKit Dynamics finds it at rest.
        private var isSettling = false
        /// How far the swipe has moved while the needle has been caught where playback is.
        private var caughtTravel: CGFloat = 0
        private var resting: Task<Void, Never>?
        private var stoppingAtAnEnd = false

        override init() {
            body = UIDynamicItemBehavior(items: [item])
            body.allowsRotation = false
            body.density = Metrics.density
            body.elasticity = 0
            body.friction = 0
            body.resistance = Metrics.resistance
            super.init()
            animator.delegate = self
            animator.addBehavior(body)
            item.onMoved = { [weak self] in self?.moved() }
        }

        /// How much of a swipe's translation the needle moves at `speed`, in points a second.
        static func gain(atSpeed speed: CGFloat) -> CGFloat {
            let gain = Metrics.slowestGain + Metrics.gainCurve * pow(abs(speed) / Metrics.gainSpeed, 3)
            return min(max(gain, Metrics.slowestGain), Metrics.fastestGain)
        }

        /// Puts the needle at `fraction` of a bar `barWidth` points long, standing still.
        func place(at fraction: Double, barWidth: CGFloat) {
            stop()
            self.barWidth = barWidth
            item.center = CGPoint(x: x(for: fraction), y: 0)
            animator.updateItem(usingCurrentState: item)
            caughtTravel = 0
        }

        /// A new touch: the needle stops coasting, quickly, as the system's does.
        func touchBegan() {
            if let push { animator.removeBehavior(push) }
            push = nil
            body.resistance = Metrics.stoppingResistance
        }

        /// The finger moved `translation` points across the touch surface, at `speed` points a second.
        /// Its first move only takes hold of the needle where it is.
        func move(by translation: CGFloat, speed: CGFloat) {
            guard barWidth > 0 else { return }
            isTracking = true
            updateInteracting()
            resting?.cancel()
            resting = Task { [weak self] in
                try? await Task.sleep(for: Metrics.restingDelay)
                guard !Task.isCancelled else { return }
                self?.lifted(speed: 0)
            }
            guard let attachment else {
                let attachment = UIAttachmentBehavior(item: item, attachedToAnchor: item.center)
                animator.addBehavior(attachment)
                self.attachment = attachment
                return
            }
            let distance = translation * Self.gain(atSpeed: speed)
            let anchor = attachment.anchorPoint.x
            let moved = min(max(anchor + distance, lowest), highest)
            let markerX = x(for: marker)
            let from = abs(anchor - markerX), to = abs(moved - markerX)
            var target = moved
            if from >= Metrics.catchDistance, to < Metrics.catchDistance, to < from, abs(speed) < Metrics.catchingSpeed {
                target = markerX
                caughtTravel = 0
            } else if isAtMarker {
                caughtTravel += distance
                if abs(caughtTravel) < Metrics.caughtTravel { target = markerX }
            }
            attachment.anchorPoint = CGPoint(x: target, y: attachment.anchorPoint.y)
        }

        /// The finger lifted at `speed` points a second: fast enough, the needle coasts on.
        func lifted(speed: CGFloat) {
            resting?.cancel()
            guard isTracking else { return }
            isTracking = false
            if let attachment {
                animator.removeBehavior(attachment)
                self.attachment = nil
                let atAnEnd = item.center.x <= lowest || item.center.x >= highest
                if abs(speed) > Metrics.coastingSpeed, !atAnEnd, push == nil {
                    body.resistance = Metrics.resistance
                    let push = UIPushBehavior(items: [item], mode: .instantaneous)
                    push.pushDirection = CGVector(dx: speed > 0 ? 1 : -1, dy: 0)
                    push.magnitude = abs(speed) * Metrics.pushPerSpeed
                    animator.addBehavior(push)
                    self.push = push
                }
            }
            // Adding a behavior sets the animator running at once; it pauses once the needle's at rest.
            isSettling = animator.isRunning
            updateInteracting()
        }

        /// Scrubbing's over: the needle stops where it is.
        func stop() {
            resting?.cancel()
            if let attachment { animator.removeBehavior(attachment) }
            attachment = nil
            halt()
            isTracking = false
            isSettling = false
            updateInteracting()
        }

        /// Whether it's caught where playback is.
        var isAtMarker: Bool {
            abs(item.center.x - x(for: marker)) < Metrics.atMarker
        }

        /// Where on the bar the needle is, from 0 to 1, as the system's turns it into a time: exactly where
        /// playback is, when it's caught there.
        var fraction: Double {
            guard barWidth > Metrics.needleWidth else { return 0 }
            if isAtMarker { return marker }
            return min(1, max(0, (item.center.x - lowest) / (highest - lowest)))
        }

        /// The needle's center at each end of the bar.
        private var lowest: CGFloat { Metrics.needleWidth / 2 }
        private var highest: CGFloat { barWidth - Metrics.needleWidth / 2 }

        private func x(for fraction: Double) -> CGFloat {
            lowest + min(1, max(0, fraction)) * (highest - lowest)
        }

        /// Stops its coast, and slows anything left at once.
        private func halt() {
            if let push { animator.removeBehavior(push) }
            push = nil
            let velocity = body.linearVelocity(for: item)
            body.addLinearVelocity(CGPoint(x: -velocity.x, y: -velocity.y), for: item)
            body.resistance = Metrics.stoppingResistance
        }

        private func moved() {
            guard barWidth > 0 else { return }
            // Past an end, it stops there, once UIKit Dynamics has finished moving it.
            if attachment == nil, item.center.x < lowest || item.center.x > highest, !stoppingAtAnEnd {
                stoppingAtAnEnd = true
                Task { [weak self] in self?.stopAtAnEnd() }
            }
            onMoved(fraction)
        }

        private func stopAtAnEnd() {
            stoppingAtAnEnd = false
            guard attachment == nil else { return }
            halt()
            item.center.x = min(max(item.center.x, lowest), highest)
            animator.updateItem(usingCurrentState: item)
        }

        private func updateInteracting() {
            let interacting = isTracking || isSettling
            guard interacting != isInteracting else { return }
            isInteracting = interacting
            onInteractingChanged(interacting)
        }

        func dynamicAnimatorDidPause(_ animator: UIDynamicAnimator) {
            isSettling = false
            updateInteracting()
        }

        /// The system's numbers.
        struct Metrics {
            /// The needle's size and density, which with the push's strength set how fast it coasts:
            /// at 3.6% of the finger's speed.
            static let needleWidth: CGFloat = 2
            static let needleHeight: CGFloat = 14
            static let density: CGFloat = 100
            /// How quickly it slows: at 5 a coast loses about a fifth of its speed a frame at 24 Hz, as the
            /// TV app's does in a recording, and goes a fifth of a second's worth of its first speed.
            static let resistance: CGFloat = 5
            /// What a new touch slows it with.
            static let stoppingResistance: CGFloat = 100
            /// The gain: a fiftieth slowly, rising with the cube of the speed to `fastestGain` at twice
            /// `gainSpeed` (1000 points a second).
            static let slowestGain: CGFloat = 0.02
            static let fastestGain: CGFloat = 0.12
            static let gainCurve: CGFloat = 0.0125
            static let gainSpeed: CGFloat = 500
            /// Lifting faster than this coasts, pushed by the speed times `pushPerSpeed`.
            static let coastingSpeed: CGFloat = 1000
            static let pushPerSpeed: CGFloat = 0.0001
            /// It catches where playback is, from `catchDistance` points or more away to within it, moving
            /// slower than `catchingSpeed`, and stays until the swipe has moved it `caughtTravel` points on.
            static let catchDistance: CGFloat = 12
            static let catchingSpeed: CGFloat = 1500
            static let caughtTravel: CGFloat = 5
            /// How near counts as there.
            static let atMarker: CGFloat = 0.01
            /// A finger resting this long has let go of the needle.
            static let restingDelay = Duration.seconds(1)
        }
    }

    /// The needle, for UIKit Dynamics: its size is what it weighs.
    private final class Item: NSObject, UIDynamicItem {
        var onMoved: () -> Void = {}
        var center: CGPoint = .zero {
            didSet { if center != oldValue { onMoved() } }
        }
        let bounds = CGRect(x: 0, y: 0, width: ScrubNeedle.Metrics.needleWidth, height: ScrubNeedle.Metrics.needleHeight)
        var transform: CGAffineTransform = .identity
    }
}
