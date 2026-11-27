import PortfolioSharedPlaybackEngine
import PortfolioSharedUI
import SwiftUI

/// A full-screen player: the picture and its subtitles, a spinner while it waits for media, why if it
/// can't play, and a transport bar like the system player's (`PlayerControlsView`), with its menus.
///
/// The Siri Remote drives it as it does the system player. Select and Play/Pause play and pause,
/// and any press shows the controls, which hide again while it plays. Clicking Left and Right skips
/// by Settings' skips, or, picking a spot, moves it; holding one pauses and sets the needle moving
/// that way (`PlayerViewModel.click(_:)` and `hold(_:)`). Swiping while paused picks a spot along
/// the bar (`ScrubNeedle`), and Select plays from it. Up, with the controls showing, moves to the
/// menu buttons beside the title (`PlayerMenusView`), which keep the controls up; Down comes back.
/// While scrubbing, Up and Down do nothing. Menu goes back out of a submenu, then closes a menu,
/// focus going back to its button; scrubbing, it puts the spot back where playback paused, the
/// title and menu buttons coming back; just paused, with nothing done since, it closes the player;
/// paused otherwise, it plays from where playback paused; playing, it hides the controls (leaving
/// the menu buttons), then closes the player, as reaching the end does. Going to the background, it
/// pauses. While a caption style has focus in a menu, how subtitles would look with it shows near
/// the top, as in the system player. Closing stops playback at once, rather than once the player
/// has faded away, and lets go of the media.
struct PlayerView: View {
    let viewModel: PlayerViewModel
    /// Closes the player.
    let onClose: () -> Void

    /// Whether a finger is moving the scrubbing needle, or it's coasting.
    @State private var isScrubbingInteractively = false
    /// The end the bar stretches past, the needle pushed on there.
    @State private var rubberBand: HorizontalEdge?
    /// Whether focus is on the menus, or in one: the screen-sized button can't take it then, or tvOS
    /// moves focus there from them, since it's all around them.
    @State private var isOnMenus = false
    /// How far up from the bottom of the screen the controls reach.
    @State private var controlsHeight: CGFloat = 0
    /// How subtitles would look with the caption style that has focus in a menu, if one has.
    @State private var previewStyle: CaptionStyle?
    @FocusState private var focus: Focus?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            // One button the size of the screen takes the remote's presses while focus isn't on the
            // menus. It's black, as clear views can't take focus.
            Button(action: viewModel.togglePlayPause) {
                Color.black
            }
            .buttonStyle(ScreenButtonStyle())
            .disabled(isOnMenus)
            .focused($focus, equals: .screen)
            .onMoveCommand(perform: moved)
            Group {
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
            }
            .allowsHitTesting(false)
            LinearGradient(colors: [.clear, .black.opacity(Metrics.scrimOpacity)], startPoint: .center, endPoint: .bottom)
                .opacity(viewModel.showsControls ? 1 : 0)
                .animation(Metrics.controlsFade, value: viewModel.showsControls)
                .allowsHitTesting(false)
            // Above the darkened bottom, and rising above the controls as they show.
            viewModel.subtitles
                .environment(\.subtitlesBottomInset, viewModel.showsControls ? controlsHeight + Metrics.subtitlesClearance : 0)
                .environment(\.drawsOriginalSubtitles, viewModel.showsOriginalSubtitles)
                .animation(Metrics.controlsFade, value: viewModel.showsControls)
                .allowsHitTesting(false)
            if let previewStyle {
                CaptionTextView(lines: [Self.previewText], style: previewStyle, size: Metrics.previewSize)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, Metrics.previewTop)
                    .id(previewStyle)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
            PlayerControlsView(
                viewModel: viewModel,
                isInteracting: isScrubbingInteractively,
                rubberBand: rubberBand,
                isBarFocused: !isOnMenus,
                focus: $focus,
                previewStyle: $previewStyle,
                onLeaveMenus: leaveMenus,
                onHeightChange: { controlsHeight = $0 }
            )
            .opacity(viewModel.showsControls ? 1 : 0)
            .animation(Metrics.controlsFade, value: viewModel.showsControls)
        }
        .animation(Metrics.previewFade, value: previewStyle)
        .background {
            RemoteReader(
                reads: !isOnMenus,
                scrubs: viewModel.isScrubbing,
                marker: { viewModel.playbackProgress },
                onBegan: swipeBegan,
                onMoved: viewModel.scrub(to:),
                onInteractingChanged: { isScrubbingInteractively = $0 },
                onRubberBand: { rubberBand = $0 },
                onClick: viewModel.click(_:),
                onHold: viewModel.hold(_:)
            )
        }
        .onPlayPauseCommand(perform: viewModel.togglePlayPause)
        .onExitCommand(perform: back)
        .defaultFocus($focus, .screen)
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player")
        .accessibilityValue(viewModel.statusName)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.close() }
        .onChange(of: isOnMenus) { _, isOnMenus in
            viewModel.holdControls(isOnMenus)
        }
        .onChange(of: viewModel.hasEnded) { _, ended in
            if ended { close() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { viewModel.enteredBackground() }
        }
    }

    /// Up, with the controls showing, moves to the menus, except while scrubbing, when Up and Down do
    /// nothing; any move shows the controls.
    private func moved(_ direction: MoveCommandDirection) {
        if direction == .up, viewModel.showsControls, !viewModel.isScrubbing, let first = viewModel.menus.first {
            isOnMenus = true
            focus = .menu(first.id)
        }
        viewModel.showControls()
    }

    /// Down from the menus, or Menu on them: focus goes back to the screen-sized button, once it can take
    /// it again.
    private func leaveMenus() {
        isOnMenus = false
        Task { focus = .screen }
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
        if viewModel.openMenuRoot != nil {
            viewModel.goBackInMenu()
        } else if viewModel.isScrubbing {
            // The spot collapses back into where playback paused as the preview goes.
            var transaction = Transaction(animation: PlayerControlsView.Metrics.scrubbingEnds)
            transaction.endsScrubbing = true
            withTransaction(transaction) { viewModel.cancelScrubbing() }
        } else if viewModel.isPausedUntouched {
            close()
        } else if viewModel.isPaused {
            if isOnMenus { leaveMenus() }
            viewModel.resume()
        } else if isOnMenus {
            leaveMenus()
            viewModel.hideControls()
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
    /// Where focus is: the screen-sized button, or a menu's button.
    enum Focus: Hashable {
        case screen
        case menu(PlayerMenu.ID)
    }

    /// What the caption style preview says, as the system player's does.
    static let previewText = AttributedString("Subtitles will look like this.")

    /// The screen-sized button, drawn as its content, with no focus effect.
    struct ScreenButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
        }
    }

    struct Metrics {
        static let messageWidth: CGFloat = 1000
        static var controlsFade: Animation { .easeInOut(duration: 0.3) }
        /// The room between subtitles and the controls under them.
        static let subtitlesClearance: CGFloat = 40
        static let scrimOpacity = 0.6
        /// The caption style preview's text before the style scales it, and how far down its top is,
        /// measured from the system player at 1080p.
        static let previewSize: CGFloat = 36
        static let previewTop: CGFloat = 218
        static var previewFade: Animation { .easeInOut(duration: 0.25) }
    }
}
