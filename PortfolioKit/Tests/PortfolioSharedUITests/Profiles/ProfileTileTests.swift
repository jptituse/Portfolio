import Testing

@testable import PortfolioSharedUI

struct ProfileTileTests {
    @Test(arguments: [
        ("Alex Rivera", "AR"),
        ("alex", "A"),
        ("Mary Ann Smith", "MA"),
        ("  sam  ", "S"),
        ("", ""),
    ])
    func usesTheFirstLettersOfTheFirstTwoWordsAsInitials(_ name: String, _ initials: String) {
        #expect(ProfileTile.initials(of: name) == initials)
    }
}
