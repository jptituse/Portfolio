//
//  PortfolioTVUITests.swift
//  PortfolioTVUITests
//
//  Created by Waynar Bocangel on 11/7/26.
//

import XCTest

/// Signing in and out, profiles, servers, Settings, Home and Search, driven with the Siri Remote.
final class AppNavigationUITests: PortfolioUITestCase {
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
        openSettings("Servers")
        openSettings("Remove All Servers")

        let confirm = app.alerts.buttons["Remove All Servers"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Removing should ask first")
        focus(confirm, moving: .up, orElse: .down)
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
    func testSettingsOpensAMenuAndMenuGoesBackToTheRowItOpenedFrom() throws {
        signInWithSampleSession()
        goToTab("Settings")

        openSettings("Video")
        XCTAssertTrue(waitForFocus(settingsRow("Dolby Vision FEL")), "Focus didn't land on the menu's first row")
        XCTAssertTrue(app.staticTexts["Video"].exists, "The title didn't change")

        press(.menu)
        XCTAssertTrue(waitForFocus(settingsRow("Video")), "Menu didn't go back to the row the menu opened from")
        XCTAssertFalse(settingsRow("Dolby Vision FEL").exists)
    }

    @MainActor
    func testSettingsRemembersAChoiceAfterARelaunch() throws {
        signInWithSampleSession()
        goToTab("Settings")
        openSettings("Video")
        XCTAssertTrue(settingsRow("Dolby Vision FEL", shows: "Off"), "FEL should start off")

        openSettings("Dolby Vision FEL")
        XCTAssertTrue(waitForFocus(settingsRow("Off")), "Focus didn't start on the choice made")
        openSettings("Full")
        XCTAssertTrue(waitForFocus(settingsRow("Dolby Vision FEL")), "Choosing didn't go back")
        XCTAssertTrue(settingsRow("Dolby Vision FEL", shows: "Full"), "The choice didn't show")

        app.terminate()
        app.launch()
        XCTAssertTrue(waitForFocus(sampleProfile, timeout: 10), "A relaunch should open on the profile picker")
        press(.select)
        XCTAssertTrue(homeRetry.waitForExistence(timeout: 10), "The profile didn't open")
        goToTab("Settings")
        openSettings("Video")
        XCTAssertTrue(settingsRow("Dolby Vision FEL").waitForExistence(timeout: 5))
        XCTAssertTrue(settingsRow("Dolby Vision FEL", shows: "Full"), "The choice wasn't remembered")
    }

    @MainActor
    func testTurningOffTheProfilePickerOpensTheLastProfileAtLaunch() throws {
        signInWithSampleSession()
        goToTab("Settings")
        openSettings("Appearance")
        focus(settingsRow("Profile Picker on Launch"), moving: .down, orElse: .up)
        press(.select)
        XCTAssertTrue(settingsRow("Profile Picker on Launch", shows: "Off"), "The setting didn't turn off")

        app.terminate()
        app.launch()

        XCTAssertTrue(homeRetry.waitForExistence(timeout: 10), "The profile opened last didn't open")
        XCTAssertFalse(sampleProfile.exists, "It opened on the profile picker")
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
    func testSearchOpensOnItsKeyboardAndSaysWhenItCannotSearch() throws {
        signInWithSampleSession()
        goToTab("Search")
        XCTAssertTrue(waitForFocus(app.keyboards.firstMatch), "Search didn't open on its keyboard")

        app.searchFields.firstMatch.typeText("dune")

        // The sample session's server doesn't exist.
        let message = app.staticTexts["Couldn't reach Preview Server. Check that it's still running, and try again."]
        XCTAssertTrue(message.waitForExistence(timeout: 10), "Search didn't say why it found nothing")
        XCTAssertFalse(app.staticTexts[tabMessages["Search"]!].exists, "What Search finds should give way once something's typed")

        // Only filters with anything in them show, and Top Results, chosen; Down from the keyboard lands
        // on it.
        XCTAssertTrue(searchFilter("Top Results").exists, "The filters didn't show once something was typed")
        XCTAssertTrue(searchFilter("Top Results").isSelected)
        XCTAssertFalse(searchFilter("Movies").exists, "A filter with nothing in it showed")
        focus(searchFilter("Top Results"), moving: .down)
        for _ in 0..<3 where !app.keyboards.firstMatch.hasFocus {
            press(.up)
        }

        // Menu from the keyboard brings in the sidebar, on Search.
        press(.menu)
        XCTAssertTrue(waitForFocus(sidebarTab("Search")), "Menu from the keyboard didn't bring in the sidebar")
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
}
