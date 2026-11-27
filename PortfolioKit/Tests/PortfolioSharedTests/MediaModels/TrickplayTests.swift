import CoreGraphics
import Foundation
import PortfolioShared
import Testing

struct TrickplayTests {
    /// 250 pictures 320 by 180, 10 seconds apart, on tiles of 10 by 10.
    let trickplay = Trickplay(
        tileURLs: (0..<3).map { URL(string: "https://media.test/trickplay/\($0).jpg")! },
        pictureWidth: 320,
        pictureHeight: 180,
        columns: 10,
        rows: 10,
        count: 250,
        interval: .seconds(10)
    )

    @Test func findsTheLastPictureTakenAtOrBeforeATime() {
        let first = trickplay.picture(at: .zero)
        #expect(first?.index == 0)
        #expect(first?.tileURL == trickplay.tileURLs[0])
        #expect(first?.rect == CGRect(x: 0, y: 0, width: 320, height: 180))

        #expect(trickplay.picture(at: .seconds(19.9))?.rect == CGRect(x: 320, y: 0, width: 320, height: 180))
        // Rows go across, then down.
        #expect(trickplay.picture(at: .seconds(125))?.rect == CGRect(x: 640, y: 180, width: 320, height: 180))
        // The next tile starts over at its top left.
        let onSecondTile = trickplay.picture(at: .seconds(1_005))
        #expect(onSecondTile?.index == 100)
        #expect(onSecondTile?.tileURL == trickplay.tileURLs[1])
        #expect(onSecondTile?.rect == CGRect(x: 0, y: 0, width: 320, height: 180))
    }

    @Test func keepsToThePicturesThereAre() {
        #expect(trickplay.picture(at: .seconds(-5))?.index == 0)
        let last = trickplay.picture(at: .seconds(99_999))
        #expect(last?.index == 249)
        #expect(last?.tileURL == trickplay.tileURLs[2])
        #expect(last?.rect == CGRect(x: 2_880, y: 720, width: 320, height: 180))
    }

    @Test func hasTheirShape() {
        #expect(trickplay.aspectRatio == 320.0 / 180)
    }
}
