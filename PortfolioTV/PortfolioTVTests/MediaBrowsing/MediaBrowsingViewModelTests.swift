import PortfolioShared
import PortfolioSharedUI
import Testing

@testable import PortfolioTV

@MainActor
struct MediaBrowsingViewModelTests {
    let group = RelatedMediaGroup(id: "group", title: "Group", items: Array(MediaItem.samples.prefix(3)))
    let other = RelatedMediaGroup(id: "other", title: "Other", items: Array(MediaItem.samples.suffix(2)))

    @Test func makesOneViewModelPerGroupInOrder() {
        let viewModel = MediaBrowsingViewModel(groups: [group, other])
        #expect(viewModel.groups.map(\.group) == [group, other])
    }

    @Test func selectingAPosterOpensItsRowWhileTheBrowsingViewIsStillAtTheRoot() {
        let viewModel = MediaBrowsingViewModel(groups: [group])
        let first = viewModel.groups[0]
        viewModel.select(group.items[1], in: first)

        #expect(viewModel.openGroup === first)
        #expect(viewModel.isOpen(first))
        #expect(viewModel.canStepBack)
        #expect(first.highlightedItem == group.items[1].id)
        #expect(first.startsLifted)
        #expect(viewModel.viewState == .root)
    }

    @Test func ignoresASelectionWhileARowIsOpen() {
        let viewModel = MediaBrowsingViewModel(groups: [group])
        let first = viewModel.groups[0]
        viewModel.select(group.items[1], in: first)
        viewModel.select(group.items[2], in: first)

        #expect(first.highlightedItem == group.items[1].id)
    }

    @Test func focusMovingToAnotherRowClearsTheOneItLeft() {
        let viewModel = MediaBrowsingViewModel(groups: [group, other])
        viewModel.focusMoved(to: .poster(group.items[0].id, group: group.id))
        viewModel.focusMoved(to: .poster(other.items[0].id, group: other.id))

        #expect(viewModel.groups[0].highlightedItem == nil)
        #expect(viewModel.groups[1].highlightedItem == other.items[0].id)
    }

    @Test func comingBackFromTheNextRowLandsOnThePosterFocusLeft() {
        let viewModel = MediaBrowsingViewModel(groups: [group, other])
        let (first, second) = (viewModel.groups[0], viewModel.groups[1])
        viewModel.focusMoved(to: .poster(group.items[2].id, group: group.id))

        viewModel.focusMoved(to: .poster(other.items[0].id, group: other.id))

        #expect(viewModel.posterToComeBack(to: first) == .poster(group.items[2].id, group: group.id))
        #expect(viewModel.posterToComeBack(to: second) == nil)
    }

    @Test func movingOnFromTheNextRowForgetsThePosterLeftBefore() {
        let third = RelatedMediaGroup(id: "third", title: "Third", items: Array(MediaItem.samples.prefix(2)))
        let viewModel = MediaBrowsingViewModel(groups: [group, other, third])
        viewModel.focusMoved(to: .poster(group.items[2].id, group: group.id))
        viewModel.focusMoved(to: .poster(other.items[1].id, group: other.id))

        viewModel.focusMoved(to: .poster(third.items[0].id, group: third.id))

        #expect(viewModel.posterToComeBack(to: viewModel.groups[0]) == nil)
        #expect(viewModel.posterToComeBack(to: viewModel.groups[1]) == .poster(other.items[1].id, group: other.id))
    }

    @Test func movingAlongTheNextRowKeepsThePosterLeftBehind() {
        let viewModel = MediaBrowsingViewModel(groups: [group, other])
        viewModel.focusMoved(to: .poster(group.items[2].id, group: group.id))
        viewModel.focusMoved(to: .poster(other.items[0].id, group: other.id))

        viewModel.focusMoved(to: .poster(other.items[1].id, group: other.id))

        #expect(viewModel.posterToComeBack(to: viewModel.groups[0]) == .poster(group.items[2].id, group: group.id))
    }

    @Test func comingBackDownFromAboveTheRowsLandsOnThePosterFocusLeft() {
        let viewModel = MediaBrowsingViewModel(groups: [group, other])
        viewModel.focusMoved(to: .poster(group.items[1].id, group: group.id))

        // Up into Home's banner, say.
        viewModel.focusMoved(to: nil)

        #expect(viewModel.posterToComeBack(to: viewModel.groups[0]) == .poster(group.items[1].id, group: group.id))
    }

    @Test func focusLeavingThePostersClearsTheHighlight() {
        let viewModel = MediaBrowsingViewModel(groups: [group])
        viewModel.focusMoved(to: .poster(group.items[0].id, group: group.id))
        viewModel.focusMoved(to: nil)

        #expect(viewModel.groups[0].highlightedItem == nil)
    }

    @Test func anOpenRowKeepsItsHighlightWhenFocusGoesToTheSidebar() {
        let viewModel = MediaBrowsingViewModel(groups: [group])
        viewModel.select(group.items[0], in: viewModel.groups[0])
        viewModel.focusMoved(to: nil)

        #expect(viewModel.groups[0].highlightedItem == group.items[0].id)
    }

    @Test func focusFallsBackToThePosterTheOpenRowIsOn() {
        let viewModel = MediaBrowsingViewModel(groups: [group])
        #expect(viewModel.posterToReturnTo == nil)

        viewModel.select(group.items[2], in: viewModel.groups[0])
        #expect(viewModel.posterToReturnTo == .poster(group.items[2].id, group: group.id))
    }

    @Test func thePostersStayFocusableUntilTheCardsTakeFocus() {
        let viewModel = MediaBrowsingViewModel(groups: [group])
        viewModel.select(group.items[0], in: viewModel.groups[0])
        #expect(viewModel.cardsHoldFocus == false)

        viewModel.groups[0].focusIsOnCards = true
        #expect(viewModel.cardsHoldFocus)
    }
}
