import PortfolioShared
import SwiftUI
import Testing

@testable import PortfolioSharedUI

@MainActor
struct MediaCardViewModelTests {
    let viewModel = MediaCardViewModel(item: MediaItem.samples[0])

    @Test func isAPosterWhileItsHierarchyIsAtTheRoot() {
        #expect(viewModel.form(in: .root) == .poster)
    }

    @Test func isAPlatterOnceItsHierarchyEntersThePreview() {
        #expect(viewModel.form(in: .preview) == .platter)
    }

    @Test func fillsTheScreenWhenAPreviewedCardIsSetToTheRoot() {
        viewModel.viewState = .root
        #expect(viewModel.form(in: .preview) == .fullScreen)
    }

    @Test func viewsAreAtTheRootUnlessTheirHierarchySaysOtherwise() {
        #expect(EnvironmentValues().viewState == .root)
    }

    @Test func updatesItsDetailTextWhenTheContentChanges() {
        viewModel.item = MediaItem.samples[1]
        #expect(viewModel.detailInfo.title == MediaItem.samples[1].name)
    }

    @Test func showsThePosterTitleOnlyOnAPoster() {
        #expect(viewModel.showsTitle(in: .root))
        #expect(!viewModel.showsTitle(in: .preview))
    }

    @Test func showsTheDetailsOnlyOnceItIsBiggerThanAPoster() {
        #expect(!viewModel.showsDetails(in: .root))
        #expect(viewModel.showsDetails(in: .preview))

        viewModel.viewState = .root
        #expect(viewModel.showsDetails(in: .preview))
    }

    @Test func hidesItsLabelsWhileTheyAreOff() {
        viewModel.showsLabels = false
        #expect(!viewModel.showsTitle(in: .root))
        #expect(!viewModel.showsDetails(in: .preview))
    }

    @Test func darkensOnlyThePlattersThatAreNotHighlighted() {
        #expect(viewModel.isDimmed(in: .preview))
        #expect(!viewModel.isDimmed(in: .root))

        viewModel.isFocused = true
        #expect(!viewModel.isDimmed(in: .preview))

        viewModel.isFocused = false
        viewModel.viewState = .root
        #expect(!viewModel.isDimmed(in: .preview))
    }

    @Test func givesAnItemTheSameArtworkHueOnEveryLaunch() {
        #expect(viewModel.artworkHue == 185.0 / 360)
    }
}
