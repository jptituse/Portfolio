import PortfolioSharedUI
import SwiftUI

/// A full-screen player: the picture, a spinner while it waits for media, why if it can't play, and a
/// transport bar like the system player's (`PlayerControlsView`).
///
/// The Siri Remote drives it as it does the system player. Select and Play/Pause play and pause, and
/// any press shows the controls, which hide again while it plays. Clicking Left and Right to skip is
/// #37. Swiping while paused picks a spot along the bar (`ScrubNeedle`), and Select plays from it. Menu
/// cancels picking a spot, then hides the controls, then closes the player, as reaching the end does.
/// Closing stops playback at once, rather than once the player has faded away, and lets go of the media.
struct PlayerView: View {
    let viewModel: PlayerViewModel
    /// Closes the player.
    let onClose: () -> Void

    /// Whether a finger is moving the scrubbing needle, or it's coasting.
    @State private var isScrubbingInteractively = false

    var body: some View {
        // One button over the whole screen takes the remote's presses: a view the size of the screen,
        // and nothing else to focus.
        Button(action: viewModel.togglePlayPause) {
            ZStack {
                Color.black
                viewModel.surface
                if viewModel.isWaiting {
                    ProgressView()
                }
                if let message = viewModel.message {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: Metrics.messageWidth)
                }
                PlayerControlsView(viewModel: viewModel, isInteracting: isScrubbingInteractively)
                    .opacity(viewModel.showsControls ? 1 : 0)
                    .animation(Metrics.controlsFade, value: viewModel.showsControls)
            }
            .background {
                SwipeReader(
                    scrubs: viewModel.isScrubbing,
                    marker: viewModel.playbackProgress,
                    onBegan: swipeBegan,
                    onMoved: viewModel.scrub(to:),
                    onInteractingChanged: { isScrubbingInteractively = $0 }
                )
            }
        }
        .buttonStyle(ScreenButtonStyle())
        .onMoveCommand { _ in viewModel.showControls() }
        .onPlayPauseCommand(perform: viewModel.togglePlayPause)
        .onExitCommand(perform: back)
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player")
        .accessibilityValue(viewModel.statusName)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.close() }
        .onChange(of: viewModel.hasEnded) { _, ended in
            if ended { close() }
        }
    }

    /// A swipe picks a spot while paused, and otherwise shows the controls. Gives where the spot is, if
    /// it's picking one.
    private func swipeBegan() -> Double? {
        if viewModel.isPaused {
            viewModel.beginScrubbing()
        } else {
            viewModel.showControls()
        }
        return viewModel.isScrubbing ? viewModel.progress : nil
    }

    private func back() {
        if viewModel.isScrubbing {
            viewModel.cancelScrubbing()
        } else if viewModel.showsControls {
            viewModel.hideControls()
        } else {
            close()
        }
    }

    private func close() {
        viewModel.close()
        onClose()
    }
}

extension PlayerView {
    /// The screen-sized button, drawn as its content, with no focus effect.
    struct ScreenButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
        }
    }

    struct Metrics {
        static let messageWidth: CGFloat = 1000
        static var controlsFade: Animation { .easeInOut(duration: 0.3) }
    }
}
