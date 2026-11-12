/// The part of the server's web client manifest (`/web/manifest.json`) that lists its icons. The
/// icons' file names change between versions, so they're read from here rather than guessed.
struct WebAppManifest: Decodable {
    struct Icon: Decodable {
        /// Relative to the manifest.
        let src: String
        /// Such as "512x512", or several sizes separated by spaces.
        let sizes: String?

        /// The widest size listed, or 0 if none can be read.
        var width: Int {
            (sizes ?? "")
                .split(separator: " ")
                .compactMap { $0.split(separator: "x").first.flatMap { Int($0) } }
                .max() ?? 0
        }
    }

    let icons: [Icon]
}
