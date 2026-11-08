/// References to an item's images. They are opaque to the UI: the server integration that produced
/// the item resolves them into image URLs. A reference changes whenever its image does, so it doubles
/// as a cache key.
public struct ImageTags: Hashable, Sendable {
    public let primary: String?
    public let logo: String?
    public let thumb: String?
    public let backdrops: [String]

    public init(primary: String? = nil, logo: String? = nil, thumb: String? = nil, backdrops: [String] = []) {
        self.primary = primary
        self.logo = logo
        self.thumb = thumb
        self.backdrops = backdrops
    }
}
