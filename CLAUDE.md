# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Portfolio is a native Jellyfin client for Apple platforms, built in SwiftUI. tvOS ships first; iOS, visionOS and macOS follow and share code through `PortfolioKit`. Playback uses AetherEngine for the best video quality, including Dolby Vision Profile 7 FEL. Broad Jellyfin plugin support and ecosystem tools like Seerr are goals.

Code conventions are in @style.md.

## Commands

Everything needs Xcode 27. There's no linter. Set the destination first:

```bash
DEST='platform=tvOS Simulator,name=Apple TV 4K (4th generation)'
```

```bash
# App unit tests, as CI runs them
xcodebuild test -workspace Portfolio.xcworkspace -scheme PortfolioTV -destination "$DEST" \
  -only-testing:PortfolioTVTests -parallel-testing-enabled NO -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO

# App UI tests. These must be signed: without signing the app can't write to the Keychain,
# so the sample sign-in silently stays on onboarding and the tests fail there.
xcodebuild test -workspace Portfolio.xcworkspace -scheme PortfolioTV -destination "$DEST" \
  -only-testing:PortfolioTVUITests -parallel-testing-enabled NO -skipPackagePluginValidation

# One UI test
xcodebuild test -workspace Portfolio.xcworkspace -scheme PortfolioTV -destination "$DEST" -parallel-testing-enabled NO \
  -skipPackagePluginValidation -only-testing:PortfolioTVUITests/AppNavigationUITests/testTheSidebarOpensOnTheCurrentSection

# Package tests (run from PortfolioKit/)
xcodebuild test -scheme PortfolioKit-Package -destination "$DEST" -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO

# One package test (Swift Testing needs the parentheses)
xcodebuild test -scheme PortfolioKit-Package -destination "$DEST" -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO \
  '-only-testing:PortfolioSharedUITests/RootViewModelTests/showsTheRightViewForEachSessionState(_:_:)'

# Release build for a real Apple TV. Release for the simulator doesn't link (#27).
xcodebuild build -workspace Portfolio.xcworkspace -scheme PortfolioTV -configuration Release \
  -destination generic/platform=tvOS -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO

# Confirm the shared UI still builds for other platforms (run from PortfolioKit/; also visionOS)
xcodebuild build -scheme PortfolioSharedUI -destination generic/platform=iOS -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO
```

CI builds the app and runs the app unit tests and package tests on every PR. UI tests aren't in CI yet (#26), so run them locally when changing anything on screen. `-test-iterations` must be at least 2. SourceKit's "No such module" errors are noise; trust `xcodebuild`.

## Architecture

`Portfolio.xcworkspace` combines `PortfolioTV/PortfolioTV.xcodeproj` (Xcode 27's `project.xcproj` format) and the local package `PortfolioKit/`. The project uses folder references, so new files under `PortfolioTV/` join their target automatically.

**Modules**
- `PortfolioShared`: models any media server could produce, plus session and Keychain persistence. No Jellyfin types.
- `PortfolioSharedJellyfinClient`: wraps jellyfin-sdk-swift and owns everything Jellyfin-specific, such as `ServerVersion` and the SDK mapping.
- `PortfolioSharedPlaybackEngine`: the engine-neutral playback layer and `PlaybackEngine` protocol.
- `PortfolioSharedAetherPlaybackEngine`: the only module that imports AetherEngine.
- `PortfolioSharedUI`: views every platform can use.
- `PortfolioTV` (app target): tvOS-only views, and the composition root. `PortfolioTVApp` builds the `SessionManager` from `KeychainStorage` and `JellyfinServerClient`, then passes `MainNavigationView` into the shared `RootView`.

The app target defaults to `MainActor` isolation and the package doesn't, so test suites for app code need `@MainActor`. Tests for app code go in `PortfolioTVTests`. Unit tests talk to `MockJellyfinServer`, an in-process fake built on `URLProtocol`.

**Browsing and card transitions** (`PortfolioTV/MediaBrowsing/`). The motion copies the Apple TV app and is plain SwiftUI state animation, with no UIKit or `matchedGeometryEffect`.
- `ViewState` (`.root`, `.preview`) is inherited through the environment. A browsing view at `.root` shows posters. Entering `.preview` turns the open row's cards into platters. Setting the previewed card's own `viewState` to `.root` expands it to full screen.
- A `RelatedMediaGroup` is drawn by `RelatedMediaGroupPosterView` at rest and by `RelatedMediaGroupCarouselView` once open. Both watch one `RelatedMediaGroupViewModel`, which holds the highlighted item, focus state, cards and where each poster is. There are two views because the open cards sit above the whole browsing view, and SwiftUI can't move a view between parents mid-animation.
- There's one `MediaCardViewModel` per item, shared by a poster and the card that grows out of it. `MediaItemLayout` is pure geometry giving each card a frame per layer, so animating the state moves every card at once.
- `MediaBrowsingViewModel` owns the order of events. Opening places the cards exactly on their posters (which hide underneath), then enters `.preview`. Closing does the reverse.

Things that break easily here:
- **Focus never moves while cards animate.** A tvOS focus update at the start of an animation stalls its first frames, so sequence with `withAnimation(_:completionCriteria:_:completion:)`.
- **Closing gives the poster focus just before removing the cards**, or tvOS picks a poster itself and the row's first one flashes. Focus passes through `nil` during this, and that gap mustn't count as focus leaving the row.
- `@FocusState` can only live in a view. View models take the binding as a parameter. Don't mirror focus into a view model property: the extra update breaks the close hand-off.
- **Labels stay out of the motion:** the ones showing fade out as cards start moving (in their own quick animation), and the next ones fade in only once cards have stopped.
- A focused poster's card starts at the size tvOS lifts it to (`posterLiftScale`, `extendedPosterLiftScale`, measured from 4K frames), so the hand-off is invisible.
- Focus staying on a poster for 5 seconds widens it in the row; this deliberately differs from the Apple TV app, and trailers will start there. **The poster row must not be a `LazyHStack`:** it re-estimates off-screen positions from a measured wide poster and the row jumps. A scroll view also can't scroll into width that's still animating in, so the row adds trailing room just before a poster widens. Don't keep that room permanently, or tvOS rests the last poster far from the edge.

**tvOS behavior that shaped the design**
- The sidebar is a `NavigationSplitView` starting at `.detailOnly`. A `.sidebarAdaptable` `TabView` always opens with focus on its sidebar, and nothing moves it out (`@FocusState`, default focus, placement APIs and UIKit focus requests were all tried).
- Sidebar rows must be `NavigationLink(value:)`: `.tag`ged labels get no focus highlight, and buttons don't change the selection. These rows bring the collapsed "‹ Home" pill, which we're keeping.
- Sections stay alive in a `ZStack`, so a hidden one must stay disabled or it can take focus.
- `navigationTransition(.zoom)` renders as a cross-fade on tvOS.

**Checking motion.** Tests can't judge it. Record the simulator during a UI test with `xcrun simctl io <udid> recordVideo --codec=h264 --force out.mp4`, stop it with SIGINT, and inspect frames with ffmpeg. Compare against a recording of the previous commit using the same test, since the simulator varies from run to run. Killing a run without stopping the recorder can leave the simulator refusing new recordings.

## Working in this repo

- Work is tracked in GitHub issues; the plan is in `docs/ROADMAP.md`, which is gitignored and may be absent. Do only the stage asked for, and don't implement ahead of it.
- The owner usually makes Xcode project and package dependency changes themselves. Give step-by-step instructions unless asked to edit those files.
- Keep each PR self-contained with one commit (a second only for follow-up tests). Fold review changes into that commit, update its message and the PR description to match, and push with `--force-with-lease`.
- Stage named paths. `DEVELOPMENT_TEAM` in `project.xcproj` is the owner's local change and must stay out of commits.
- Tests run on every PR with no hidden configuration such as unshared scheme environment variables. Don't add integration or live-server tests until that infrastructure exists (#21).

## Settled decisions

- TestFlight only, never the App Store. The license is GPLv3 with an App Store/DRM exception. Licensing isn't a concern for this distribution model, so don't raise it.
- AetherEngine is pinned exactly. Its patent-flagged traits are all compiled in, with runtime settings to enable them.
- Minimums: tvOS 26 and Jellyfin server 10.10.
