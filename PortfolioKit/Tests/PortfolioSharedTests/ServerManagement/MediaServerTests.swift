import PortfolioSharedTestSupport
import Testing

@testable import PortfolioShared

struct MediaServerTests {
    let alex = User(id: "alex", name: "Alex", serverID: "server-1", primaryImageTag: nil)
    let sam = User(id: "sam", name: "Sam", serverID: "server-1", primaryImageTag: nil)
    let kim = User(id: "kim", name: "Kim", serverID: "server-1", primaryImageTag: nil)

    @Test func hasASessionOnlyForSignedInUsers() {
        let saved = MediaServer(server: .sample(), users: [alex, sam], accessTokens: ["alex": "token"])

        #expect(saved.session(for: "alex") == UserSession(server: .sample(), user: alex, accessToken: "token"))
        #expect(saved.session(for: "sam") == nil)
        #expect(saved.isSignedIn("alex"))
        #expect(!saved.isSignedIn("sam"))
    }

    @Test func remembersANewUserOrUpdatesAKnownOne() {
        var saved = MediaServer(server: .sample(), users: [alex])
        let renamed = User(id: "alex", name: "Alex R.", serverID: "server-1", primaryImageTag: "new")

        saved.remember(sam)
        saved.remember(renamed)

        #expect(saved.users == [renamed, sam])
    }

    @Test func takesTheListedUsersInOrderAndKeepsEveryoneElse() {
        // Kim signed in here but is hidden from the server's sign-in screen.
        var saved = MediaServer(server: .sample(), users: [alex, kim], accessTokens: ["kim": "token"])

        saved.update(listedUsers: [sam, alex])

        #expect(saved.users == [sam, alex, kim])
        #expect(saved.isSignedIn("kim"))
    }
}
