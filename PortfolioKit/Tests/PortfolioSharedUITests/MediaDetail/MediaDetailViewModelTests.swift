import PortfolioShared
import Testing

@testable import PortfolioSharedUI

@MainActor
struct MediaDetailViewModelTests {
    let viewModel = MediaDetailViewModel(item: MediaItem.samples[0])

    @Test func showsTheItemAsTheFirstDetailView() {
        #expect(viewModel.title == MediaItem.samples[0].name)
        #expect(viewModel.heading == "Detail view 1")
    }

    @Test func goingDeeperShowsTheSameItemOneLevelFurtherDown() {
        let deeper = viewModel.deeper().deeper()
        #expect(deeper.title == MediaItem.samples[0].name)
        #expect(deeper.heading == "Detail view 3")
    }
}
