import JellyfinAPI

/// Wraps jellyfin-sdk-swift. No `JellyfinAPI` type crosses this module's public API: callers see
/// `PortfolioShared` types, so the SDK can be upgraded or replaced without touching features.
public enum PortfolioSharedJellyfinClientModule {
    public static let name = "PortfolioSharedJellyfinClient"
}
