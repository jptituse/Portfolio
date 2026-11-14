import SwiftUI
import UIKit

/// The system's page indicator: a dot for each page on a translucent platter. While it counts down to
/// the next page, the current one is a dash that fills over `interval`, as the Apple TV app's does.
/// It only shows where things are and how long's left; the banner moves on by itself, and the
/// indicator doesn't take focus.
struct PageIndicatorView: UIViewRepresentable {
    let count: Int
    let current: Int
    let isCountingDown: Bool
    /// Goes up each time the countdown starts again, emptying the dash.
    let countdown: Int
    let interval: Duration

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIPageControl {
        let control = UIPageControl()
        control.backgroundStyle = .prominent
        control.hidesForSinglePage = true
        control.isUserInteractionEnabled = false
        let progress = UIPageControlTimerProgress(preferredDuration: interval / .seconds(1))
        progress.resetsToInitialPageAfterEnd = false
        progress.delegate = context.coordinator
        control.progress = progress
        return control
    }

    func updateUIView(_ control: UIPageControl, context: Context) {
        control.numberOfPages = count
        let progress = control.progress as? UIPageControlTimerProgress
        if control.currentPage != current || context.coordinator.countdown != countdown {
            control.currentPage = current
            context.coordinator.countdown = countdown
            progress?.currentProgress = 0
        }
        if isCountingDown {
            progress?.resumeTimer()
        } else {
            progress?.pauseTimer()
        }
    }

    final class Coordinator: NSObject, UIPageControlTimerProgressDelegate {
        var countdown = 0

        /// The banner moves on by itself, in step with this; the indicator only shows it.
        func pageControlTimerProgress(_ progress: UIPageControlTimerProgress, shouldAdvanceToPage page: Int) -> Bool {
            false
        }
    }
}
