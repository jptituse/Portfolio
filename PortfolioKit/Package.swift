// swift-tools-version: 6.2

import PackageDescription

// Shared code for every Portfolio app target (tvOS first; iOS and visionOS later).
// App targets stay thin: they link `PortfolioSharedUI` for screens and
// `PortfolioSharedAetherPlaybackEngine` to provide the player engine.
// Module dependency direction is documented in docs/ROADMAP.md §2.
let package = Package(
    name: "PortfolioKit",
    defaultLocalization: "en",
    platforms: [
        .tvOS(.v26),
        .iOS(.v26),
        .visionOS(.v26),
    ],
    products: [
        .library(name: "PortfolioSharedUI", targets: ["PortfolioSharedUI"]),
        .library(name: "PortfolioSharedAetherPlaybackEngine", targets: ["PortfolioSharedAetherPlaybackEngine"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jellyfin/jellyfin-sdk-swift", .upToNextMinor(from: "3.4.0")),
        // The HTTP layer under jellyfin-sdk-swift. Declared directly because its `APIError` carries
        // the status codes that `JellyfinError` classifies.
        .package(url: "https://github.com/kean/Get", from: "2.2.1"),
        // Pinned exactly: the engine moves fast and ships a prebuilt FFmpeg, so updates are deliberate.
        // All optional traits are compiled in; using each one will be a runtime setting.
        .package(
            url: "https://github.com/superuser404notfound/AetherEngine",
            exact: "7.59.0",
            traits: [
                "DualLayerDolbyVision",
                "TrueHDObjectAudio",
                "DTSXObjectAudio",
                "DolbyVisionStillReshaping",
            ]
        ),
    ],
    targets: [
        .target(name: "PortfolioShared"),
        .target(
            name: "PortfolioSharedJellyfinClient",
            dependencies: [
                "PortfolioShared",
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
                .product(name: "Get", package: "Get"),
            ]
        ),
        .target(
            name: "PortfolioSharedPlaybackEngine",
            dependencies: ["PortfolioShared", "PortfolioSharedJellyfinClient"]
        ),
        .target(
            name: "PortfolioSharedAetherPlaybackEngine",
            dependencies: [
                "PortfolioSharedPlaybackEngine",
                .product(name: "AetherEngine", package: "AetherEngine"),
            ]
        ),
        .target(
            name: "PortfolioSharedUI",
            dependencies: [
                "PortfolioShared",
                "PortfolioSharedJellyfinClient",
                "PortfolioSharedPlaybackEngine",
            ]
        ),

        .testTarget(name: "PortfolioSharedTests", dependencies: ["PortfolioShared"]),
        .testTarget(
            name: "PortfolioSharedJellyfinClientTests",
            dependencies: [
                "PortfolioSharedJellyfinClient",
                .product(name: "JellyfinAPI", package: "jellyfin-sdk-swift"),
                .product(name: "Get", package: "Get"),
            ],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "PortfolioSharedPlaybackEngineTests", dependencies: ["PortfolioSharedPlaybackEngine"]),
        .testTarget(name: "PortfolioSharedAetherPlaybackEngineTests", dependencies: ["PortfolioSharedAetherPlaybackEngine"]),
        .testTarget(name: "PortfolioSharedUITests", dependencies: ["PortfolioSharedUI"]),
    ],
    swiftLanguageModes: [.v6]
)
