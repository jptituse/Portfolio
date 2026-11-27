import PortfolioShared
import PortfolioSharedUI
import SwiftUI

extension EnvironmentValues {
    /// Builds, opens and lets go of full-screen cards' pages, over the section.
    @Entry var detailPages = DetailPagesAction()
    /// Asks for a card's details, so it shows its format badges and credits, and its page opens on them.
    @Entry var prepareDetails = PrepareDetailsAction()
    /// The open profile's own settings, such as its ratings.
    @Entry var profilePreferences: ProfilePreferences?
}

/// Builds, opens and lets go of full-screen cards' pages, over the section, from the open profile's
/// server. It's equal for the same profile, so the views that read it don't update each time it's set.
struct DetailPagesAction: Equatable {
    private let navigation: MainNavigationViewModel?
    private let profile: CurrentProfileViewModel?

    init(navigation: MainNavigationViewModel? = nil, profile: CurrentProfileViewModel? = nil) {
        self.navigation = navigation
        self.profile = profile
    }

    /// Builds `card`'s page ahead, hidden, to open at `destination`: while it's full screen, or while
    /// focus rests on an episode in its show's row.
    @MainActor func prepare(_ card: MediaCardViewModel, opensAt destination: MediaDetailDestination = .sections) {
        guard let navigation, let profile else { return }
        navigation.prepareDetails(of: card, opensAt: destination) {
            profile.makeDetail(for: card, listsEpisodes: destination != .card)
        }
    }

    /// Lets go of `card`'s page, built ahead, once it's no longer full screen or focus has left it in
    /// its show's row.
    @MainActor func discard(_ card: MediaCardViewModel) {
        navigation?.discardDetails(of: card)
    }

    /// Shows `card`'s page, at `destination`.
    ///
    /// - Parameters:
    ///   - action: the card's action that has focus, which the page's starts on.
    ///   - returnFocus: gives focus back to the card's actions once the page has gone, to the action the
    ///     page's had, if any.
    @MainActor func open(
        _ card: MediaCardViewModel,
        at destination: MediaDetailDestination,
        from action: MediaDetailAction?,
        returnFocus: @escaping (MediaDetailAction?) -> Void
    ) {
        guard let navigation, let profile else { return }
        // An episode's own page, opened from its show's list of episodes, doesn't list them again.
        navigation.openDetails(
            of: card,
            at: destination,
            from: action,
            making: { profile.makeDetail(for: card, listsEpisodes: destination != .card) },
            returnFocus: returnFocus
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.navigation === rhs.navigation && lhs.profile === rhs.profile
    }
}

/// Asks the open profile's server for a card's details. It's equal for the same profile.
struct PrepareDetailsAction: Equatable {
    private let profile: CurrentProfileViewModel?

    init(_ profile: CurrentProfileViewModel? = nil) {
        self.profile = profile
    }

    @MainActor func callAsFunction(_ card: MediaCardViewModel) {
        profile?.prepareDetails(for: card)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.profile === rhs.profile
    }
}
