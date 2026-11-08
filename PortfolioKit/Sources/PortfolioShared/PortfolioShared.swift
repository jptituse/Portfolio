/// The base module every other module builds on.
///
/// - Domain types shared everywhere (servers, users, libraries, items). No SDK types.
/// - Local persistence: Keychain-backed session storage now, SwiftData later. Kept in its own
///   folder with a small API so the plain data types stay free of storage concerns.
public enum PortfolioSharedModule {
    public static let name = "PortfolioShared"
}
