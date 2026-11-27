import XCTest

/// Browsing a row of posters, its preview and full-screen cards, with the Siri Remote. The sample
/// session's server doesn't exist, so the app shows the sample row on Home in place of what Home loads.
final class BrowsingUITests: PortfolioUITestCase {
    override var launchEnvironment: [String: String] {
        ["PORTFOLIO_SAMPLE_ROW": "1"]
    }

    override var home: XCUIElement {
        poster("Sample Movie 1")
    }

    @MainActor
    func testTheSidebarOpensOnTheCurrentSection() throws {
        signInWithSampleSession()
        goToTab("Settings")
        goToTab("Home")
        XCTAssertTrue(waitForFocus(poster("Sample Movie 1")), "Choosing a section didn't move focus to it")

        // Left, from the first poster.
        press(.left)
        XCTAssertTrue(waitForFocus(sidebarTab("Home")), "Left didn't land on the current section")

        // And Menu, from further along the row.
        press(.right)
        XCTAssertTrue(waitForFocus(poster("Sample Movie 1")))
        press(.right)
        XCTAssertTrue(waitForFocus(poster("Sample Movie 2")))
        press(.menu)
        XCTAssertTrue(waitForFocus(sidebarTab("Home")), "Menu didn't land on the current section")
    }

    @MainActor
    func testAPosterWidensWhenFocusStaysOnItAndTheRowClosesBackOntoIt() throws {
        focusFirstPoster()
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
        focusFirstPoster()
        press(.right, times: 5)
        XCTAssertTrue(waitForFocus(poster("Sample Movie 6")))
        let normalWidth = poster("Sample Movie 6").frame.width

        XCTAssertTrue(waitForWidth(of: poster("Sample Movie 6"), toExceed: normalWidth * 1.5), "The poster didn't widen")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.frame.contains(poster("Sample Movie 6").frame), "The wide poster ran off the screen")
    }

    @MainActor
    func testMovingPastAWidePosterAtTheEdgeAndBackKeepsTheRowInPlace() throws {
        focusFirstPoster()
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
        focusFirstPoster()
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
        focusFirstPoster()
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
    func testAPosterGoesFromPreviewToFullDetailAndBack() throws {
        signInWithSampleSession()
        openCarousel()

        // Left and Right move between the platters of the row.
        press(.right)
        XCTAssertTrue(platter("Sample Movie 2").hasFocus, "Right didn't move to the next platter")

        // Down grows the focused platter into the full-screen detail.
        press(.down)
        XCTAssertTrue(fullScreenDetail.waitForExistence(timeout: 5), "Down didn't expand the platter")
        XCTAssertTrue(app.staticTexts["Sample Movie 2"].exists)

        // Information opens the item's page below the card. Every platter shows the actions too, so this
        // is the full-screen card's.
        focus(fullScreenDetail.buttons["Information"], moving: .right, orElse: .down)
        press(.select)
        XCTAssertTrue(detailPage.waitForExistence(timeout: 5), "Information didn't open the item's page")

        // Menu steps back: the page scrolls back up to the card, then the full detail, the preview and
        // the poster.
        press(.menu)
        XCTAssertTrue(detailPage.waitForNonExistence(timeout: 5), "Menu didn't go back up to the card")
        XCTAssertTrue(fullScreenDetail.exists, "The card wasn't there under its page")
        press(.menu)
        XCTAssertTrue(fullScreenDetail.waitForNonExistence(timeout: 5), "Menu didn't shrink the full detail")
        XCTAssertTrue(waitForFocus(platter("Sample Movie 2")), "The preview lost its place")
        press(.menu)
        XCTAssertTrue(platter("Sample Movie 2").waitForNonExistence(timeout: 5), "Menu didn't close the preview")
        XCTAssertTrue(waitForFocus(poster("Sample Movie 2")), "Closing didn't land on the poster you ended on")
    }

    @MainActor
    func testThePreviewOpensOnThePosterYouChoseAndClosesBackOntoIt() throws {
        signInWithSampleSession()

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
        focus(fullScreenDetail.buttons["Information"], moving: .right, orElse: .down)
        for _ in 0..<4 where !sidebarHasFocus() {
            press(.left)
        }
        XCTAssertTrue(sidebarHasFocus(), "Left from the full detail didn't bring in the sidebar")
        XCTAssertTrue(fullScreenDetail.exists, "The full detail should stay underneath the sidebar")
    }
}
