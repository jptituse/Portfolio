# Style

How Portfolio's Swift code is organized and written.

## Where code goes

- `PortfolioSharedUI` holds UI that works on every platform without significant editing; a few compile-time guards are fine. Anything else belongs in platform code, such as the `PortfolioTV` target.
- "Reusable" means it would work on the other platform, not just compile. The carousel can be made to build for iOS with three guards, but it's driven by focus and the Menu button, so it's tvOS code.
- A shared view that needs platform content takes it as a view builder, the way `RootView` takes the main UI.
- `PortfolioShared` models must be ones any media server could produce. Before adding one, ask whether a non-Jellyfin backend would need it in the same shape; a Plex fork should be easy. Jellyfin specifics go in `PortfolioSharedJellyfinClient`.
- Group views in folders named for their use case. `Components` is fine for generic pieces. Never use the name `DesignSystem`.

## Naming

- If two names are confusing, either the modeling is wrong or the naming is wrong. Fix whichever it is.
- Models describe the domain, not how it's drawn: `RelatedMediaGroup`, not `MediaRow`. The row is how tvOS shows it.
- Don't keep two models for what is really one thing. State about a thing lives with it (a highlighted item and focus state on the row's view model, not a separate `OpenRow`).
- Prefer the vocabulary already in use: `MediaItemLayout`, not `CardLayout`.
- A piece of UI is a view, never a "screen": `HeaderView`, `view(for:)`. "Screen" only means the display itself, as in full screen or off screen.
- A view is named for the concept it shows, and its view model for that concept alone: `RelatedMediaGroupPosterView` and `RelatedMediaGroupCarouselView` both show a group, so both watch a `RelatedMediaGroupViewModel`.
- Don't add a type just to hold a collection or to keep it from being observed. Put it on the view model it belongs to, marked `@ObservationIgnored` if changes to it shouldn't redraw anything.

## Views

Each view has its own file, `<Purpose>View.swift`, with the type named to match. It holds only UI logic.

The state machine driving a view goes in `<Purpose>ViewModel.swift`, as a `@MainActor @Observable final class`, and the view watches it. View models also do the formatting, so views are handed ready-made strings.

Views are purely UI. They don't hold model data, derive state from it or work anything out from it: a view reads what its view model has ready (`viewModel.isDimmed(in: layer)`, `viewModel.heading`) and calls its methods. That covers navigation state too: how deep a detail view is lives in `MediaDetailViewModel`, which also makes the next one. A view still owns what only a view can have, like `@FocusState`, environment values and scroll positions, and passes them to its view model when it needs them.

Constants that drive a view go in a `Metrics` struct inside an extension of that view:

```swift
extension RelatedMediaGroupPosterView {
    struct Metrics {
        static let posterSpacing: CGFloat = 40
    }
}
```

With more than a few (five or so), move the extension to `<Purpose>View+Metrics.swift`. Inside generic views, use computed `static var`, because generic types can't have stored statics.

A helper type only one view needs, such as a `ButtonStyle`, is nested in an extension of that view instead of being a top-level type. Prefer a system style if it looks the same.

## Things that aren't built yet

Don't add `Placeholder…` types that will be deleted. Make the real type and put a `// FIXME:` in it saying what real content it needs, with the issue number. If something only draws a stand-in, such as a background, make it a method on the view that uses it.

## Formatting

Don't indent code inside compile-time guards:

```swift
#if DEBUG
if let override = environment["KEY"] {
    return override
}
#endif
```

A `guard`'s `else` goes on the same line as its last condition, never on its own line:

```swift
guard let nearest = frames.keys.min(),
    let known = frames[nearest] else {
    return .zero
}
```

## Tests

Use Swift Testing, with test names that read as sentences: `@Test func keepsAnOpenedSectionAfterMovingAway()`.
