//
//  PortfolioTVUITests.swift
//  PortfolioTVUITests
//
//  Created by Waynar Bocangel on 11/7/26.
//

import XCTest

/// Drives the app with the Siri Remote, the way a viewer would.
final class AppNavigationUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // A Keychain service of its own, so every run starts signed out.
        app.launchEnvironment["PORTFOLIO_KEYCHAIN_SERVICE"] = "ui-tests-\(UUID().uuidString)"
        app.launch()
    }

    @MainActor
    func testSigningOutReturnsToTheProfilePicker() throws {
        signInWithSampleSession()

        signOut()

        XCTAssertTrue(sampleProfile.waitForExistence(timeout: 10), "The profile should stay on the picker")
        XCTAssertTrue(app.buttons["Someone Else"].exists)
        XCTAssertFalse(poster("Sample Movie 1").exists)
    }

    @MainActor
    func testRemovingAllServersStartsOver() throws {
        signInWithSampleSession()
        goToTab("Settings")
        focus(app.buttons["Remove All Servers (Debug)"], moving: .right, orElse: .up)
        press(.select)

        // The confirmation's button shows up twice, nested in itself.
        let confirm = app.sheets.buttons["Remove All Servers"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Removing should ask first")
        focus(confirm, moving: .up)
        press(.select)

        XCTAssertTrue(app.buttons["Sign In on This TV"].waitForExistence(timeout: 10), "The app should start over")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Sign In on This TV"].waitForExistence(timeout: 10), "Nothing should come back at a relaunch")
        XCTAssertFalse(sampleProfile.exists)
    }

    @MainActor
    func testAProfileSignedInOnThisDeviceOpensAfterARelaunch() throws {
        signInWithSampleSession()

        app.terminate()
        app.launch()

        XCTAssertTrue(sampleProfile.waitForExistence(timeout: 10), "A relaunch should open on the profile picker")
        XCTAssertTrue(waitForFocus(sampleProfile))
        press(.select)
        XCTAssertTrue(homeRetry.waitForExistence(timeout: 10), "The profile didn't open")
    }

    @MainActor
    func testTheProfileInTheSidebarSwitchesProfiles() throws {
        signInWithSampleSession()

        for _ in 0..<3 where !sidebarHasFocus() {
            press(.menu)
        }
        XCTAssertTrue(sidebarHasFocus(), "Couldn't bring focus to the sidebar")
        let profile = app.buttons["sidebar.profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5), "The sidebar should show the open profile")
        focus(profile, moving: .up)
        press(.select)

        XCTAssertTrue(sampleProfile.waitForExistence(timeout: 10), "Selecting the profile should open the profile picker")
        XCTAssertTrue(waitForFocus(sampleProfile))
        // It's still signed in, so it opens straight away, on a fresh Home.
        press(.select)
        XCTAssertTrue(waitForFocus(homeRetry), "The profile didn't open again on Home")
    }

    @MainActor
    func testASignedOutProfileAsksForItsPassword() throws {
        signInWithSampleSession()
        signOut()

        XCTAssertTrue(sampleProfile.waitForExistence(timeout: 10))
        focus(sampleProfile, moving: .left)
        press(.select)

        XCTAssertTrue(app.secureTextFields["onboarding.password"].waitForExistence(timeout: 10), "No password field")
        XCTAssertFalse(app.textFields["onboarding.username"].exists, "The username is known already")
        XCTAssertTrue(app.staticTexts["Preview User"].exists)
    }

    @MainActor
    func testSomeoneElsePicksAnAddedServerOrAddsAnother() throws {
        signInWithSampleSession()
        signOut()

        let someoneElse = app.buttons["Someone Else"]
        XCTAssertTrue(someoneElse.waitForExistence(timeout: 10))
        focus(someoneElse, moving: .right)
        press(.select)

        let sampleServer = app.buttons["Preview Server"]
        let addServer = app.buttons["Add Server"]
        XCTAssertTrue(sampleServer.waitForExistence(timeout: 10), "The added server should be on the server picker")
        XCTAssertTrue(addServer.exists)

        // Adding another server starts at the welcome screen; Menu goes back.
        focus(addServer, moving: .right)
        press(.select)
        XCTAssertTrue(app.buttons["Sign In on This TV"].waitForExistence(timeout: 10))
        press(.menu)
        XCTAssertTrue(sampleServer.waitForExistence(timeout: 10), "Menu should go back to the server picker")

        // On an added server, someone else types their username.
        focus(sampleServer, moving: .left)
        press(.select)
        XCTAssertTrue(app.textFields["onboarding.username"].waitForExistence(timeout: 10), "No username field")

        press(.menu)
        press(.menu)
        XCTAssertTrue(sampleProfile.waitForExistence(timeout: 10), "Menu should go back to the profile picker")
    }

    @MainActor
    func testAnAddressWhereNothingAnswersSaysSo() throws {
        let signInHere = app.buttons["Sign In on This TV"]
        XCTAssertTrue(signInHere.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForFocus(signInHere), "A fresh install should open on signing in on this TV")
        press(.select)

        let address = app.textFields["onboarding.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForFocus(address), "The server step should open on the address field")

        // Nothing listens on port 9 of this machine.
        press(.select)
        app.typeText("127.0.0.1:9")
        press(.menu)
        focus(app.buttons["onboarding.continue"], moving: .down)
        press(.select)

        let error = app.staticTexts["onboarding.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 30), "No error appeared. Hierarchy:\n\(app.debugDescription)")
        XCTAssertTrue(error.label.hasPrefix("Couldn't reach a server"), "Wrong error: \(error.label)")
    }

    @MainActor
    func testTheAppOpensWithFocusOnHome() throws {
        signInWithSampleSession()

        XCTAssertTrue(waitForFocus(homeRetry), "The app didn't open with focus on Home")
        XCTAssertFalse(sidebarHasFocus(), "The sidebar shouldn't have focus when the app opens")
    }

    @MainActor
    func testHomeSaysWhenItCannotReachTheServer() throws {
        signInWithSampleSession()

        let message = app.staticTexts["Couldn't reach Preview Server. Check that it's still running, and try again."]
        XCTAssertTrue(message.waitForExistence(timeout: 10), "Home didn't say why it's empty")
        XCTAssertFalse(poster("Sample Movie 1").exists, "Home shouldn't show sample items")

        // Trying again asks the server again, which still isn't there.
        XCTAssertTrue(waitForFocus(homeRetry))
        press(.select)
        XCTAssertTrue(message.waitForExistence(timeout: 10))
        XCTAssertTrue(homeRetry.exists)
    }

    @MainActor
    func testTheSidebarOpensOnTheCurrentSection() throws {
        signInWithSampleSession()
        goToTab("Libraries")
        XCTAssertTrue(waitForFocus(poster("Sample Movie 1")), "Choosing a section didn't move focus to it")

        // Left, from the first poster.
        press(.left)
        XCTAssertTrue(waitForFocus(sidebarTab("Libraries")), "Left didn't land on the current section")

        // And Menu, from further along the row.
        press(.right)
        XCTAssertTrue(waitForFocus(poster("Sample Movie 1")))
        press(.right)
        XCTAssertTrue(waitForFocus(poster("Sample Movie 2")))
        press(.menu)
        XCTAssertTrue(waitForFocus(sidebarTab("Libraries")), "Menu didn't land on the current section")
    }

    @MainActor
    func testAPosterWidensWhenFocusStaysOnItAndTheRowClosesBackOntoIt() throws {
        focusFirstPosterInLibraries()
        press(.right, times: 2)
        XCTAssertTrue(waitForFocus(poster("Sample Movie 3")))
        let normalWidth = poster("Sample Movie 3").frame.width

        XCTAssertTrue(waitForWidth(of: poster("Sample Movie 3"), toExceed: normalWidth * 1.5), "The poster didn't widen")

        // It opens and closes on the wide poster.
        press(.select)
        XCTAssertTrue(waitForFocus(platter("Sample Movie 3")), "The wide poster didn't open")
        closePreview(onto: "Sample Movie 3")
        XCTAssertGreaterThan(poster("Sample Movie 3").frame.width, normalWidth * 1.5, "Closing didn't land on the wide poster")

        // Moving on puts it back.
        press(.right)
        XCTAssertTrue(waitForFocus(poster("Sample Movie 4")))
        XCTAssertLessThan(poster("Sample Movie 3").frame.width, normalWidth * 1.5, "The poster stayed wide after focus left")
    }

    @MainActor
    func testAWidePosterNearTheEdgeOfTheScreenStaysInView() throws {
        focusFirstPosterInLibraries()
        press(.right, times: 5)
        XCTAssertTrue(waitForFocus(poster("Sample Movie 6")))
        let normalWidth = poster("Sample Movie 6").frame.width

        XCTAssertTrue(waitForWidth(of: poster("Sample Movie 6"), toExceed: normalWidth * 1.5), "The poster didn't widen")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.frame.contains(poster("Sample Movie 6").frame), "The wide poster ran off the screen")
    }

    @MainActor
    func testMovingPastAWidePosterAtTheEdgeAndBackKeepsTheRowInPlace() throws {
        focusFirstPosterInLibraries()
        press(.right, times: 5)
        XCTAssertTrue(waitForFocus(poster("Sample Movie 6")))
        let normalWidth = poster("Sample Movie 6").frame.width
        XCTAssertTrue(waitForWidth(of: poster("Sample Movie 6"), toExceed: normalWidth * 1.5), "The poster didn't widen")
        Thread.sleep(forTimeInterval: 1.5)

        press(.right)
        XCTAssertTrue(waitForFocus(poster("Sample Movie 7")))
        Thread.sleep(forTimeInterval: 1.5)
        let positionBefore = poster("Sample Movie 5").frame.minX

        // Everything is already on screen, so going back must not move the row.
        press(.left)
        XCTAssertTrue(waitForFocus(poster("Sample Movie 6")))
        Thread.sleep(forTimeInterval: 1.5)

        XCTAssertEqual(poster("Sample Movie 5").frame.minX, positionBefore, accuracy: 2, "The row jumped")
        XCTAssertTrue(app.frame.contains(poster("Sample Movie 6").frame), "The poster ended up off screen")
    }

    @MainActor
    func testTheLastPosterOfARowStaysInViewWhenItWidens() throws {
        focusFirstPosterInLibraries()
        press(.right, times: 19)
        XCTAssertTrue(waitForFocus(poster("Sample Movie 20")))
        let normalWidth = poster("Sample Movie 20").frame.width

        XCTAssertTrue(waitForWidth(of: poster("Sample Movie 20"), toExceed: normalWidth * 1.5), "The poster didn't widen")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.frame.contains(poster("Sample Movie 20").frame), "The wide poster ran off the screen")

        // Closing lands on it in view, both when it was already wide and when it's only just been reached.
        press(.select)
        XCTAssertTrue(waitForFocus(platter("Sample Movie 20")))
        closePreview(onto: "Sample Movie 20")

        press(.left)
        XCTAssertTrue(waitForFocus(poster("Sample Movie 19")))
        press(.select)
        XCTAssertTrue(waitForFocus(platter("Sample Movie 19")))
        press(.right)
        XCTAssertTrue(waitForFocus(platter("Sample Movie 20")))
        closePreview(onto: "Sample Movie 20")
    }

    @MainActor
    func testClosingLandsOnAWidePosterEvenIfFocusDidNotStayOnIt() throws {
        focusFirstPosterInLibraries()
        let normalWidth = poster("Sample Movie 1").frame.width

        // Opened straight away, then moved to the next platter.
        press(.select)
        XCTAssertTrue(waitForFocus(platter("Sample Movie 1")))
        press(.right)
        XCTAssertTrue(waitForFocus(platter("Sample Movie 2")))
        closePreview(onto: "Sample Movie 2")

        XCTAssertGreaterThan(poster("Sample Movie 2").frame.width, normalWidth * 1.5, "Closing didn't land on a wide poster")
        XCTAssertLessThan(poster("Sample Movie 1").frame.width, normalWidth * 1.5, "The poster it opened on stayed wide")
    }

    @MainActor
    func testEveryTabGoesFromPosterToPreviewToFullDetailAndBack() throws {
        signInWithSampleSession()

        for tab in ["Libraries", "Search", "Settings"] {
            goToTab(tab)
            openCarousel()

            // Left and Right move between the platters of the row.
            press(.right)
            XCTAssertTrue(platter("Sample Movie 2").hasFocus, "Right didn't move to the next platter in \(tab)")

            // Down grows the focused platter into the full-screen detail.
            press(.down)
            XCTAssertTrue(fullScreenDetail.waitForExistence(timeout: 5), "Down didn't expand the platter in \(tab)")
            XCTAssertTrue(app.staticTexts["Sample Movie 2"].exists)

            // Go deeper pushes plain detail views on top.
            focus(app.buttons["Go deeper"], moving: .right, orElse: .down)
            press(.select)
            XCTAssertTrue(app.staticTexts["Detail view 1"].waitForExistence(timeout: 5), "Couldn't go deeper in \(tab)")

            // Menu steps back: deeper view, full detail, preview, poster.
            press(.menu)
            XCTAssertTrue(fullScreenDetail.waitForExistence(timeout: 5), "Menu didn't return to the full detail in \(tab)")
            press(.menu)
            XCTAssertTrue(fullScreenDetail.waitForNonExistence(timeout: 5), "Menu didn't shrink the full detail in \(tab)")
            XCTAssertTrue(waitForFocus(platter("Sample Movie 2")), "The preview lost its place in \(tab)")
            press(.menu)
            XCTAssertTrue(platter("Sample Movie 2").waitForNonExistence(timeout: 5), "Menu didn't close the preview in \(tab)")
            XCTAssertTrue(waitForFocus(poster("Sample Movie 2")), "Closing didn't land on the poster you ended on in \(tab)")
        }
    }

    @MainActor
    func testThePreviewOpensOnThePosterYouChoseAndClosesBackOntoIt() throws {
        signInWithSampleSession()
        goToTab("Libraries")

        focus(poster("Sample Movie 3"), moving: .right)
        press(.select)
        XCTAssertTrue(platter("Sample Movie 3").waitForExistence(timeout: 5))
        XCTAssertTrue(waitForFocus(platter("Sample Movie 3")), "The preview didn't open on the chosen poster")

        press(.menu)
        XCTAssertTrue(platter("Sample Movie 3").waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitForFocus(poster("Sample Movie 3")), "Closing didn't return to the chosen poster")
    }

    @MainActor
    func testAScrolledRowOpensAndClosesOnTheChosenPoster() throws {
        signInWithSampleSession()
        goToTab("Libraries")

        // Move far enough along that the row has scrolled past its first posters.
        focus(poster("Sample Movie 1"), moving: .right, orElse: .down)
        press(.right, times: 11)
        XCTAssertTrue(waitForFocus(poster("Sample Movie 12")), "The row didn't scroll to the twelfth poster")

        press(.select)
        XCTAssertTrue(waitForFocus(platter("Sample Movie 12")), "The preview didn't open on the chosen poster")

        // Slide to a poster that wasn't on screen when the row opened: it closes back onto it.
        press(.right, times: 6)
        XCTAssertTrue(waitForFocus(platter("Sample Movie 18")), "Right didn't slide along the open row")
        closePreview(onto: "Sample Movie 18")

        // And the same going back the other way.
        press(.select)
        XCTAssertTrue(waitForFocus(platter("Sample Movie 18")), "The preview didn't reopen on the chosen poster")
        press(.left, times: 10)
        XCTAssertTrue(waitForFocus(platter("Sample Movie 8")), "Left didn't slide along the open row")
        closePreview(onto: "Sample Movie 8")
    }

    @MainActor
    func testSelectExpandsAPlatterAndLeftBringsInTheSidebar() throws {
        signInWithSampleSession()
        goToTab("Libraries")
        openCarousel()

        // Left from the first platter brings in the sidebar; Right goes back to the platter.
        press(.left)
        XCTAssertTrue(sidebarHasFocus(), "Left from the first platter didn't bring in the sidebar")
        press(.right)
        XCTAssertTrue(platter("Sample Movie 1").hasFocus)

        // Select expands too, and Left from the full detail brings in the sidebar over it.
        press(.select)
        XCTAssertTrue(fullScreenDetail.waitForExistence(timeout: 5), "Select didn't expand the platter")
        XCTAssertTrue(app.staticTexts["Sample Movie 1"].exists)
        focus(app.buttons["Go deeper"], moving: .right, orElse: .down)
        for _ in 0..<4 where !sidebarHasFocus() {
            press(.left)
        }
        XCTAssertTrue(sidebarHasFocus(), "Left from the full detail didn't bring in the sidebar")
        XCTAssertTrue(fullScreenDetail.exists, "The full detail should stay underneath the sidebar")
    }

    // MARK: Helpers

    private func signInWithSampleSession() {
        let sampleSession = app.buttons["Continue with a Sample Session (Debug)"]
        XCTAssertTrue(sampleSession.waitForExistence(timeout: 10))
        focus(sampleSession, moving: .down)
        press(.select)
        XCTAssertTrue(homeRetry.waitForExistence(timeout: 10), "The signed-in app didn't appear")
    }

    /// Home's Try Again button. The sample session's server doesn't exist, so Home says it can't reach
    /// it and offers to try again.
    private var homeRetry: XCUIElement {
        app.buttons["home.retry"]
    }

    /// The sample session's tile on the profile picker.
    private var sampleProfile: XCUIElement {
        app.buttons["Preview User"]
    }

    /// Signs out with the debug button in Settings, back to the profile picker.
    private func signOut() {
        goToTab("Settings")
        focus(app.buttons["Sign Out (Debug)"], moving: .right, orElse: .up)
        press(.select)
    }

    private func focusFirstPosterInLibraries() {
        signInWithSampleSession()
        goToTab("Libraries")
        focus(poster("Sample Movie 1"), moving: .right, orElse: .down)
    }

    private var fullScreenDetail: XCUIElement {
        app.descendants(matching: .any)["detail.fullScreen"]
    }

    private func platter(_ title: String) -> XCUIElement {
        app.buttons.matching(identifier: "carousel.platter").matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// Focus lands at the end of a transition, so this waits for it rather than checking once.
    private func waitForFocus(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let focused = expectation(for: NSPredicate(format: "hasFocus == true"), evaluatedWith: element)
        return XCTWaiter().wait(for: [focused], timeout: timeout) == .completed
    }

    /// A poster widens a few seconds after it gets focus.
    private func waitForWidth(of element: XCUIElement, toExceed width: CGFloat, timeout: TimeInterval = 9) -> Bool {
        let wider = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in element.frame.width > width }, object: nil)
        return XCTWaiter().wait(for: [wider], timeout: timeout) == .completed
    }

    private func poster(_ title: String) -> XCUIElement {
        app.buttons.matching(identifier: "browse.poster").matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// From a tab's browsing view, selects the first poster and checks it opens as a platter.
    private func openCarousel() {
        // Down from a header's buttons can land on a later poster.
        focus(poster("Sample Movie 1"), moving: .right, orElse: .down, .left)
        press(.select)
        XCTAssertTrue(platter("Sample Movie 1").waitForExistence(timeout: 5), "The poster didn't open")
        XCTAssertTrue(waitForFocus(platter("Sample Movie 1")), "The preview didn't start on the chosen item")
    }

    /// From the preview, presses Menu and checks the row closes onto `title`'s poster, in view.
    private func closePreview(onto title: String) {
        press(.menu)
        XCTAssertTrue(platter(title).waitForNonExistence(timeout: 5), "Menu didn't close the preview")
        XCTAssertTrue(waitForFocus(poster(title)), "Closing didn't land on \(title)")
        XCTAssertTrue(app.frame.contains(poster(title).frame), "\(title) closed off screen")
    }

    private func sidebarTab(_ title: String) -> XCUIElement {
        app.cells.containing(NSPredicate(format: "label == %@", title)).firstMatch
    }

    private let sidebarSections = ["Search", "Home", "Libraries", "Settings"]

    /// Text only that tab's view shows, to confirm which tab is showing.
    private let tabMessages = [
        "Home": "What's new in your libraries.",
        "Libraries": "Your movie, show and other libraries will appear here.",
        "Search": "Search for movies, shows, episodes and people.",
        "Settings": "Your server, account and playback settings will appear here.",
    ]

    /// Opens the sidebar (Menu from a tab's root brings focus back to it), moves to `title` and selects it.
    private func goToTab(_ title: String) {
        for _ in 0..<3 where !sidebarHasFocus() {
            press(.menu)
        }
        XCTAssertTrue(sidebarHasFocus(), "Couldn't bring focus to the sidebar")
        focus(sidebarTab(title), moving: .down, orElse: .up)
        press(.select)
        let message = app.staticTexts[tabMessages[title] ?? title]
        XCTAssertTrue(message.waitForExistence(timeout: 5), "\(title) didn't open. Hierarchy:\n\(app.debugDescription)")
    }

    private func sidebarHasFocus() -> Bool {
        sidebarSections.contains { sidebarTab($0).hasFocus }
    }

    /// Presses `direction` (then each of `fallbacks` in turn) until `element` has focus.
    private func focus(_ element: XCUIElement, moving direction: XCUIRemote.Button, orElse fallbacks: XCUIRemote.Button...) {
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

    private func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0..<times {
            remote.press(button)
            // Let focus and navigation animations settle before the next check.
            Thread.sleep(forTimeInterval: 0.6)
        }
    }
}
