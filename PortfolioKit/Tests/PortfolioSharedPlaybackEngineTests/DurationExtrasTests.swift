import Testing

@testable import PortfolioSharedPlaybackEngine

struct DurationExtrasTests {
    @Test(arguments: [0.0, 1.5, 347.25, 7_200.125])
    func measuresADurationInSeconds(_ seconds: Double) {
        #expect(abs(Duration.seconds(seconds).inSeconds - seconds) < 1e-9)
    }
}
