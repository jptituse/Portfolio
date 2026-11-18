import XCTest

/// Plays Jellyfin's public test videos in the player, one per launch. The app plays only what its
/// server sends; in a debug build, a test can hand it a URL to play instead, so playback is checked
/// without a server. These need the network, and an Apple TV: the simulator has no hardware video
/// decoders, so AetherEngine decodes in software there, and its frame conversion traps in the
/// simulator's Metal.
final class PlaybackUITests: XCTestCase {
    private let remote = XCUIRemote.shared

    /// Jellyfin's test videos (repo.jellyfin.org/test-videos), 1080p: SDR, HDR10 and Dolby Vision.
    static let testVideos: [(name: String, path: String)] = [
        ("SDR H.264", "SDR/AVC/Test Jellyfin 1080p AVC 3M.mp4"),
        ("SDR HEVC 10-bit", "SDR/HEVC 10bit/Test Jellyfin 1080p HEVC 10bit 3M.mp4"),
        ("SDR AV1", "SDR/AV1/Test Jellyfin 1080p AV1 10bit 3M.mp4"),
        ("HDR10 HEVC", "HDR/HDR10/HEVC/Test Jellyfin 1080p HEVC HDR10 3M.mp4"),
        ("Dolby Vision Profile 8.1", "HDR/Dolby Vision/Test Jellyfin 1080p DV P8.1.mp4"),
        ("Dolby Vision Profile 5", "HDR/Dolby Vision/Test Jellyfin 1080p DV P5.mp4"),
    ]

    static func url(of path: String) -> String {
        "https://repo.jellyfin.org/test-videos/" + path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
    }

    override func setUpWithError() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Video can't play in the simulator: AetherEngine's software decoding traps in its Metal. Run on an Apple TV.")
        #else
        continueAfterFailure = true
        #endif
    }

    @MainActor
    func testPlaysEachTestVideoAndMenuClosesThePlayer() throws {
        for video in Self.testVideos {
            let app = XCUIApplication()
            app.launchEnvironment["PORTFOLIO_KEYCHAIN_SERVICE"] = "ui-tests-\(UUID().uuidString)"
            app.launchEnvironment["PORTFOLIO_PLAYBACK_TEST_URL"] = Self.url(of: video.path)
            app.launch()
            signInWithSampleSession(in: app)

            let player = app.otherElements["player"]
            XCTAssertTrue(player.waitForExistence(timeout: 20), "The player didn't open for \(video.name)")
            let playing = NSPredicate(format: "value == 'playing'")
            let started = expectation(for: playing, evaluatedWith: player)
            wait(for: [started], timeout: 45)
            XCTAssertEqual(player.value as? String, "playing", "\(video.name) didn't play")

            remote.press(.menu)
            XCTAssertTrue(player.waitForNonExistence(timeout: 10), "Menu didn't close the player for \(video.name)")
            app.terminate()
        }
    }

    /// Signs in with the debug sample session, whose server doesn't exist.
    private func signInWithSampleSession(in app: XCUIApplication) {
        let sampleSession = app.buttons["Continue with a Sample Session (Debug)"]
        XCTAssertTrue(sampleSession.waitForExistence(timeout: 10))
        for _ in 0..<6 where !sampleSession.hasFocus {
            remote.press(.down)
        }
        remote.press(.select)
    }
}
