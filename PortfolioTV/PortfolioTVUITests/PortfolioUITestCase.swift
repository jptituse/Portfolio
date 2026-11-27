import XCTest

/// Drives the app with the Siri Remote, the way a viewer would. Each test launches it with a Keychain
/// service and settings of its own, so it starts signed out, with Settings as they come.
class PortfolioUITestCase: XCTestCase {
    var app: XCUIApplication!
    let remote = XCUIRemote.shared

    /// What a test class adds to the app's launch environment.
    var launchEnvironment: [String: String] { [:] }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["PORTFOLIO_KEYCHAIN_SERVICE"] = "ui-tests-\(UUID().uuidString)"
        app.launchEnvironment["PORTFOLIO_DEFAULTS_SUITE"] = "ui-tests-\(UUID().uuidString)"
        app.launchEnvironment.merge(launchEnvironment) { $1 }
        app.launch()
    }


    func signInWithSampleSession() {
        let sampleSession = app.buttons["Continue with a Sample Session (Debug)"]
        XCTAssertTrue(sampleSession.waitForExistence(timeout: 10))
        focus(sampleSession, moving: .down)
        press(.select)
        XCTAssertTrue(home.waitForExistence(timeout: 10), "The signed-in app didn't appear")
    }

    /// What shows once Home has opened: its Try Again button, since the sample session's server
    /// doesn't exist, unless a test class shows the sample row there.
    var home: XCUIElement {
        homeRetry
    }

    /// An item's page, below its full-screen card.
    var detailPage: XCUIElement {
        app.descendants(matching: .any)["detail.page"]
    }

    /// Home's Try Again button. The sample session's server doesn't exist, so Home says it can't reach
    /// it and offers to try again.
    var homeRetry: XCUIElement {
        app.buttons["home.retry"]
    }

    /// The sample session's tile on the profile picker.
    var sampleProfile: XCUIElement {
        app.buttons["Preview User"]
    }

    /// Signs the sample profile out in Settings, back to the profile picker. It's the only account on
    /// its server, so Settings offers to remove the server too; it doesn't.
    func signOut() {
        goToTab("Settings")
        openSettings("Accounts & Profiles")
        // The account, listed after the profile.
        focus(settingsRow("Preview User", index: 1), moving: .down, orElse: .up)
        press(.select)
        openSettings("Sign Out")
        let signOutOnly = app.alerts.buttons["Sign Out Only"].firstMatch
        XCTAssertTrue(signOutOnly.waitForExistence(timeout: 5), "Signing out should ask first")
        focus(signOutOnly, moving: .down, orElse: .up)
        press(.select)
    }

    /// A row of the Settings menu showing, by its title: the list's cell, which is what takes focus,
    /// labeled with the row's title, then its value. Asking for the cell around the row's button
    /// instead (`containing`) took minutes.
    func settingsRow(_ title: String, index: Int = 0) -> XCUIElement {
        app.cells.matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", title, "\(title), ")).element(boundBy: index)
    }

    /// Whether a Settings row shows `value`.
    func settingsRow(_ title: String, shows value: String) -> Bool {
        settingsRow(title).label == "\(title), \(value)"
    }

    /// Moves focus to a Settings row, by its title, and selects it, then lets the next menu arrive. Right
    /// first, out of the sidebar, where focus stays as a section opens.
    func openSettings(_ title: String) {
        focus(settingsRow(title), moving: .right, orElse: .down, .up)
        press(.select)
    }

    /// Signs in and moves focus to the sample row's first poster.
    func focusFirstPoster() {
        signInWithSampleSession()
        focus(poster("Sample Movie 1"), moving: .right, orElse: .down)
    }

    var fullScreenDetail: XCUIElement {
        app.descendants(matching: .any)["detail.fullScreen"]
    }

    func platter(_ title: String) -> XCUIElement {
        app.buttons.matching(identifier: "carousel.platter").matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// Focus lands at the end of a transition, so this waits for it rather than checking once.
    func waitForFocus(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let focused = expectation(for: NSPredicate(format: "hasFocus == true"), evaluatedWith: element)
        return XCTWaiter().wait(for: [focused], timeout: timeout) == .completed
    }

    /// A poster widens a few seconds after it gets focus.
    func waitForWidth(of element: XCUIElement, toExceed width: CGFloat, timeout: TimeInterval = 9) -> Bool {
        let wider = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in element.frame.width > width }, object: nil)
        return XCTWaiter().wait(for: [wider], timeout: timeout) == .completed
    }

    /// One of Search's filters, by its title.
    func searchFilter(_ title: String) -> XCUIElement {
        app.buttons.matching(identifier: "search.filter").matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    func poster(_ title: String) -> XCUIElement {
        app.buttons.matching(identifier: "browse.poster").matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// From a tab's browsing view, selects the first poster and checks it opens as a platter.
    func openCarousel() {
        // Down from a header's buttons can land on a later poster.
        focus(poster("Sample Movie 1"), moving: .right, orElse: .down, .left)
        press(.select)
        XCTAssertTrue(platter("Sample Movie 1").waitForExistence(timeout: 5), "The poster didn't open")
        XCTAssertTrue(waitForFocus(platter("Sample Movie 1")), "The preview didn't start on the chosen item")
    }

    /// From the preview, presses Menu and checks the row closes onto `title`'s poster, in view.
    func closePreview(onto title: String) {
        press(.menu)
        XCTAssertTrue(platter(title).waitForNonExistence(timeout: 5), "Menu didn't close the preview")
        XCTAssertTrue(waitForFocus(poster(title)), "Closing didn't land on \(title)")
        XCTAssertTrue(app.frame.contains(poster(title).frame), "\(title) closed off screen")
    }

    func sidebarTab(_ title: String) -> XCUIElement {
        app.cells.containing(NSPredicate(format: "label == %@", title)).firstMatch
    }

    let sidebarSections = ["Search", "Home", "Settings"]

    /// Text only that tab's view shows, to confirm which tab is showing.
    let tabMessages = [
        // Until something's typed.
        "Search": "Search for movies, shows, episodes and people.",
    ]

    /// Opens the sidebar (Menu from a tab's root brings focus back to it), moves to `title` and selects it.
    func goToTab(_ title: String) {
        for _ in 0..<3 where !sidebarHasFocus() {
            press(.menu)
        }
        XCTAssertTrue(sidebarHasFocus(), "Couldn't bring focus to the sidebar")
        focus(sidebarTab(title), moving: .down, orElse: .up)
        press(.select)
        // Settings' first menu, what Home shows, else the message only that tab's view shows.
        let shown = switch title {
        case "Settings": settingsRow("Appearance")
        case "Home": home
        default: app.staticTexts[tabMessages[title] ?? title]
        }
        XCTAssertTrue(shown.waitForExistence(timeout: 5), "\(title) didn't open. Hierarchy:\n\(app.debugDescription)")
    }

    func sidebarHasFocus() -> Bool {
        sidebarSections.contains { sidebarTab($0).hasFocus }
    }

    /// Presses `direction` (then each of `fallbacks` in turn) until `element` has focus.
    func focus(_ element: XCUIElement, moving direction: XCUIRemote.Button, orElse fallbacks: XCUIRemote.Button...) {
        guard element.waitForExistence(timeout: 5) else {
            XCTFail("\(element) doesn't exist. Hierarchy:\n\(app.debugDescription)")
            return
        }
        for button in [direction] + fallbacks {
            for _ in 0..<6 {
                if element.hasFocus { return }
                press(button)
            }
        }
        XCTAssertTrue(element.hasFocus, "Couldn't move focus to \(element)")
    }

    func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0..<times {
            remote.press(button)
            // Let focus and navigation animations settle before the next check.
            Thread.sleep(forTimeInterval: 0.6)
        }
    }
}
