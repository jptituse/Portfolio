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

A simulator build with `CODE_SIGNING_ALLOWED=NO` and a signed UI test run share DerivedData, and the UI tests can end up launching the unsigned app, which the simulator refuses ("Security policy issue", or a launch `RequestDenied`). Run `xcodebuild build-for-testing` without that flag to sign it again.

Interrupting a build (killing `xcodebuild`, or a "build database is locked" failure from two builds at once) can leave later builds reporting success without relinking the app, so the simulator runs old code. Check `PortfolioTV.app/PortfolioTV.debug.dylib`'s timestamp in this project's DerivedData folder (there can be more than one), and if it's stale, delete `Build/Intermediates.noindex/PortfolioTV.build/Debug-appletvsimulator` and the built `.app` there. A clean build of everything takes about a minute, so a build running far longer is stuck rather than slow: delete that DerivedData folder's `Build` (keeping `SourcePackages`) and build again.

## Architecture

`Portfolio.xcworkspace` combines `PortfolioTV/PortfolioTV.xcodeproj` (Xcode 27's `project.xcproj` format) and the local package `PortfolioKit/`. The project uses folder references, so new files under `PortfolioTV/` join their target automatically.

**Modules**
- `PortfolioShared`: models any media server could produce, plus the saved servers, sessions and Keychain persistence. No Jellyfin types.
- `PortfolioSharedJellyfinClient`: wraps jellyfin-sdk-swift and owns everything Jellyfin-specific, such as `ServerVersion` and the SDK mapping.
- `PortfolioSharedPlaybackEngine`: the engine-neutral playback layer and `PlaybackEngine` protocol.
- `PortfolioSharedAetherPlaybackEngine`: the only module that imports AetherEngine.
- `PortfolioSharedUI`: views every platform can use, and the view models of screens each platform draws its own way (profiles and onboarding), so another platform only adds views.
- `PortfolioTV` (app target): tvOS-only views, and the composition root. `PortfolioTVApp` makes the one `JellyfinServerClient` and the `SessionManager` (Keychain storage, with the client as its authority), and passes both to the shared `RootView` along with how to make its `ProfilesView` and `MainNavigationView`. `RootViewModel` hands the services to the view models it makes: a fresh `ProfilesViewModel` each time no profile is open, and a `CurrentProfileViewModel` for each fresh main UI, so every profile opens on Home.

The app target defaults to `MainActor` isolation and the package doesn't, so test suites for app code need `@MainActor`. Tests for app code go in `PortfolioTVTests`. Unit tests talk to `MockJellyfinServer`, an in-process fake built on `URLProtocol` that listens on a given scheme, host and port. It and `JellyfinServerClient.mocked`, which sends requests to it, are in `PortfolioSharedTestSupport`.

`PortfolioTV/Info.plist` sits outside the app's folder and holds only what build settings can't express: App Transport Security allows plain HTTP, because most Jellyfin servers on a home network are `http://…:8096`. Xcode merges it with the Info.plist it generates.

**Profiles and onboarding** (`PortfolioTV/Profiles/`, `PortfolioTV/Onboarding/`, view models in `PortfolioSharedUI`).
- Every launch opens on the profile picker ("Who's watching?"): everyone on every server added to this device, signed in or not, plus "Someone Else". A fresh install opens on the welcome screen instead. No profile is open until one is picked (`SessionState.choosingProfile`). The picker starts with focus on the profile opened last (`SessionManager.lastOpenedProfile`, saved by `MediaServerStore` under its own key), without opening it.
- The open profile sits at the top of the sidebar (`CurrentProfileView`), its server's name reading "Switch Profile" while focused. Selecting it closes the profile without signing it out (`SessionManager.closeProfile()`), back to the profile picker.
- "Someone Else" on the profile picker leads to a server picker (`ServerPickerViewModel`): the servers added to this device, with their icons, where someone types their username (anyone the server lists is on the profile picker already), and "Add Server", which starts at the welcome screen.
- `SessionManager` holds the saved servers (`MediaServer`: the server, the users this device knows, and the access token of each signed-in user), stored in the Keychain by `MediaServerStore`. Opening a profile checks its token with the server first; offline still opens, and a revoked token asks for the password. Signing out keeps the profile on the picker. Settings' "Remove All Servers (Debug)" (`SessionManager.removeAllServers()`) starts over as if freshly installed; deleting the app doesn't, because the Keychain outlives it.
- Adding a server goes welcome → address and port (without a scheme, HTTPS first, then HTTP on 8096; see `ServerAddress`) → the users the server lists (`/Users/Public`), or straight to signing in with a username when it lists nobody → their password, beside the server's branding (its icon, and its splash image and login message, if set). "Someone Else" covers users the server hides.
- `ProfilesViewModel.path` holds the pushed steps (`ProfilesViewModel.Step`) with their view models. Navigation values must be `Hashable`, so `Step` compares by view model identity: each step is equal only to itself.
- User pictures and the splash come through `JellyfinServerClient.imageURL`, as PNG at full size: those endpoints have no size or quality options, and PNG keeps the server from compressing them again. The splash fills the sign-in screen's right half without stretching (`scaledToFill`), blurred and dimmed under the server's icon and name: filling a nearly square half crops and enlarges a 16:9 image.
- The server's icon is the largest one its web client lists in `/web/manifest.json` (the file names carry a content hash in some versions, so they aren't guessed). A server without its web client gets a stand-in.
- "Use Your Phone" is a disabled stand-in for Quick Connect (#8).

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
- The sidebar is a `NavigationSplitView` starting at `.detailOnly`. Search is its first section, as in the Apple TV app, but the app opens on Home. Its rows are spaced apart with `listRowSpacing`, which tvOS only has from 27. A `.sidebarAdaptable` `TabView` always opens with focus on its sidebar, and nothing moves it out (`@FocusState`, default focus, placement APIs and UIKit focus requests were all tried).
- Sidebar rows must be `NavigationLink(value:)`: `.tag`ged labels get no focus highlight, and buttons don't change the selection. These rows bring the collapsed "‹ Home" pill, which we're keeping.
- A button as a row of its own in that sidebar doesn't take focus at all, so the open profile is a button in the section's header. Header content sits closer to the edges than rows, so `CurrentProfileView`'s insets are measured to give its focus highlight the rows' exact edges.
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
