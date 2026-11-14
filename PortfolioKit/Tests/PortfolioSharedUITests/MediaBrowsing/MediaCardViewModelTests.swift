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

    @Test func showsTheLogoOnlyOnceThePosterWidens() {
        #expect(!viewModel.showsLogo(in: .root))

        viewModel.isExtended = true

        #expect(viewModel.showsLogo(in: .root))
        // Platters show their details instead.
        #expect(!viewModel.showsLogo(in: .preview))
    }

    @Test func showsTheDetailsOnlyOnceItIsBiggerThanAPoster() {
        #expect(!viewModel.showsDetails(in: .root))
        #expect(viewModel.showsDetails(in: .preview))

        viewModel.viewState = .root
        #expect(viewModel.showsDetails(in: .preview))
    }

    @Test func hidesItsLabelsWhileTheyAreOff() {
        viewModel.isExtended = true
        viewModel.showsLabels = false
        #expect(!viewModel.showsLogo(in: .root))
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

    @Test func showsItsActionsWithItsDetailsAsDarkenedAsItIs() {
        #expect(viewModel.actionsOpacity(in: .root) == 0)

        viewModel.isFocused = true
        #expect(viewModel.actionsOpacity(in: .preview) == 1)

        viewModel.isFocused = false
        #expect(viewModel.actionsOpacity(in: .preview) == 1 - MediaCardView.Metrics.dimmedOpacity)

        viewModel.showsLabels = false
        #expect(viewModel.actionsOpacity(in: .preview) == 0)
    }

    // MARK: Artwork

    /// Answers with a URL naming what was asked for, for any image the item has.
    struct DescribingImages: MediaImageResolver {
        func url(for item: MediaItem, _ kind: MediaImageKind, pixelSize: CGSize) -> URL? {
            guard item.hasImage(kind) else { return nil }
            let kind = "\(kind)".replacing(" ", with: "")
            return URL(string: "https://images.test/\(item.id)/\(kind)/\(Int(pixelSize.width))x\(Int(pixelSize.height))")
        }
    }

    func card(_ images: [MediaImageKind: String]) -> MediaCardViewModel {
        let card = MediaCardViewModel(item: MediaItem(id: "movie", name: "Arrival", kind: .movie, images: images), images: DescribingImages())
        card.posterArtworkSize = CGSize(width: 500, height: 800)
        card.landscapeArtworkSize = CGSize(width: 3900, height: 2200)
        return card
    }

    @Test func fetchesThePosterAtAPostersSize() {
        #expect(card([.primary: "p"]).posterArtworkURL?.absoluteString == "https://images.test/movie/primary/500x800")
    }

    @Test func fetchesLandscapeArtAtTheScreensSize() {
        let url = card([.primary: "p", .backdrop(): "b"]).landscapeArtworkURL
        #expect(url?.absoluteString == "https://images.test/movie/backdrop(index:0)/3900x2200")
    }

    @Test func prefersTheBackdropThenTheThumbnailThenThePosterForLandscapeArt() {
        #expect(card([.primary: "p", .thumb: "t", .backdrop(): "b"]).landscapeArtworkKind == .backdrop())
        #expect(card([.primary: "p", .thumb: "t"]).landscapeArtworkKind == .thumb)
        #expect(card([.primary: "p"]).landscapeArtworkKind == .primary)
    }

    @Test func waitsForTheSizesBeforeFetchingArtwork() {
        let card = MediaCardViewModel(item: MediaItem(id: "movie", name: "Arrival", kind: .movie, images: [.primary: "p"]), images: DescribingImages())
        #expect(card.posterArtworkURL == nil)
        #expect(card.landscapeArtworkURL == nil)
    }

    @Test func showsLandscapeArtOnceThePosterWidens() {
        let card = card([.primary: "p", .backdrop(): "b"])
        #expect(!card.showsLandscapeArtwork(in: .root))

        card.isExtended = true

        #expect(card.showsLandscapeArtwork(in: .root))
    }

    @Test func showsLandscapeArtAsAPlatterAndFullScreen() {
        let card = card([.primary: "p", .backdrop(): "b"])
        #expect(card.showsLandscapeArtwork(in: .preview))

        card.viewState = .root

        #expect(card.showsLandscapeArtwork(in: .preview))
    }

    @Test func loadsLandscapeArtAheadOfTimeOnlyWhileWarm() {
        let card = card([.primary: "p", .backdrop(): "b"])
        #expect(!card.loadsLandscapeArtwork(in: .root))

        card.isWarm = true

        #expect(card.loadsLandscapeArtwork(in: .root))
        #expect(!card.showsLandscapeArtwork(in: .root))
    }

    @Test func fetchesTheLogoAtTheMostItTakesUp() {
        let card = card([.primary: "p", .logo: "l"])
        card.logoArtworkSize = CGSize(width: 500, height: 200)
        #expect(card.logoArtworkURL?.absoluteString == "https://images.test/movie/logo/500x200")
    }

    @Test func showsTheLogoInPlaceOfTheTitleInTheDetails() {
        let card = card([.primary: "p", .logo: "l"])
        #expect(card.detailInfo.logoURL == nil)

        card.logoArtworkSize = CGSize(width: 1100, height: 400)

        #expect(card.detailInfo.logoURL == card.logoArtworkURL)
        #expect(card.detailInfo.logoURL != nil)
    }

    @Test func showsTheTitleInTheDetailsWithoutALogo() {
        let card = card([.primary: "p"])
        card.logoArtworkSize = CGSize(width: 1100, height: 400)
        #expect(card.detailInfo.logoURL == nil)
    }

    @Test func hasNoLogoForAnItemWithoutOneSoItsTitleShows() {
        let card = card([.primary: "p"])
        card.logoArtworkSize = CGSize(width: 500, height: 200)
        #expect(card.logoArtworkURL == nil)
    }

    @Test func takesThePostersShapeFromTheItem() {
        let still = MediaItem(id: "episode", name: "Pilot", kind: .episode, primaryImageAspectRatio: 16.0 / 9)
        #expect(MediaCardViewModel(item: still).posterAspectRatio == 16.0 / 9)
    }

    @Test func drawsAMoviePostersShapeWhenTheItemDoesNotSay() {
        #expect(viewModel.posterAspectRatio == 2.0 / 3)
    }

    @Test(arguments: [(0.1, 0.5), (5.0, 2.4)])
    func keepsUnusualShapesWithinReason(_ ratio: Double, _ drawn: CGFloat) {
        let item = MediaItem(id: "odd", name: "Odd", kind: .movie, primaryImageAspectRatio: ratio)
        #expect(MediaCardViewModel(item: item).posterAspectRatio == drawn)
    }

    // MARK: Progress

    func card(runtime minutes: Int?, watched watchedMinutes: Int = 0, episode: EpisodeInfo? = nil) -> MediaCardViewModel {
        MediaCardViewModel(item: MediaItem(
            id: "item",
            name: "Item",
            kind: episode == nil ? .movie : .episode,
            runtime: minutes.map { .seconds($0 * 60) },
            userData: UserData(playbackPosition: .seconds(watchedMinutes * 60)),
            episode: episode
        ))
    }

    @Test func showsHowFarAlongAnItemIs() {
        let card = card(runtime: 100, watched: 25)
        #expect(card.progress == 0.25)
        #expect(card.timeLeftLabel == "1h 15m left")
    }

    @Test func showsNoProgressForAnItemNotStartedYet() {
        let card = card(runtime: 45)
        #expect(card.progress == nil)
        #expect(card.timeLeftLabel == "45m left")
    }

    @Test func roundsTheTimeLeftUp() {
        let card = MediaCardViewModel(item: MediaItem(
            id: "item", name: "Item", kind: .movie, runtime: .seconds(600), userData: UserData(playbackPosition: .seconds(590))
        ))
        #expect(card.timeLeftLabel == "1m left")
    }

    @Test func showsNoTimeLeftWithoutAKnownLength() {
        #expect(card(runtime: nil).timeLeftLabel == nil)
    }

    @Test(arguments: [
        (EpisodeInfo(seasonNumber: 1, episodeNumber: 5), "S1E5"),
        (EpisodeInfo(seasonNumber: 12, episodeNumber: 103), "S12E103"),
        (EpisodeInfo(episodeNumber: 5), "E5"),
        (EpisodeInfo(seasonNumber: 1), nil),
    ])
    func namesAnEpisodeBySeasonAndNumber(_ episode: EpisodeInfo, _ label: String?) {
        #expect(card(runtime: 45, episode: episode).episodeLabel == label)
    }

    @Test func namesNoEpisodeForAMovie() {
        #expect(card(runtime: 120).episodeLabel == nil)
    }

    @Test func showsProgressOnlyOnAPosterThatShowsIt() {
        let card = card(runtime: 100, watched: 25)
        #expect(!card.showsProgressIndicator(in: .root))

        card.showsProgress = true
        #expect(card.showsProgressIndicator(in: .root))
        #expect(!card.showsProgressIndicator(in: .preview))

        card.showsLabels = false
        #expect(!card.showsProgressIndicator(in: .root))
    }

    @Test func fetchesLandscapeArtSmallerWhileAWideCardRests() {
        let card = card([.primary: "p", .backdrop(): "b"])
        card.restingLandscapeArtworkSize = CGSize(width: 1000, height: 600)
        #expect(card.landscapeArtworkURL?.absoluteString == "https://images.test/movie/backdrop(index:0)/1000x600")

        // Warm, it may grow, so it comes at the screen's size.
        card.isWarm = true
        #expect(card.landscapeArtworkURL?.absoluteString == "https://images.test/movie/backdrop(index:0)/3900x2200")
    }

    @Test func goesFromPosterToPlatterToFullScreen() {
        let card = card([.primary: "p", .backdrop(): "b"])
        #expect(card.form(in: .root) == .poster)
        #expect(card.form(in: .preview) == .platter)

        card.viewState = .root

        #expect(card.form(in: .preview) == .fullScreen)
    }

    @Test func goesStraightFromPosterToFullScreenWhenItsOwnLayerIsRootAlready() {
        let card = card([.primary: "p", .backdrop(): "b"])
        card.viewState = .root

        // Still a poster until its hierarchy enters the preview, and then full screen, never a platter.
        #expect(card.form(in: .root) == .poster)
        #expect(!card.showsLandscapeArtwork(in: .root))
        #expect(card.form(in: .preview) == .fullScreen)
        #expect(card.showsLandscapeArtwork(in: .preview))
    }

    @Test func hasNoArtworkWithoutSomewhereToGetIt() {
        viewModel.posterArtworkSize = CGSize(width: 500, height: 800)
        #expect(viewModel.posterArtworkURL == nil)
    }
}
