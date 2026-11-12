//
//  PortfolioTVApp.swift
//  PortfolioTV
//
//  Created by Waynar Bocangel on 11/7/26.
//

import PortfolioShared
import PortfolioSharedJellyfinClient
import PortfolioSharedUI
import SwiftUI

@main
struct PortfolioTVApp: App {
    /// The app talks to Jellyfin and keeps its session in the Keychain. This is the one place that
    /// choice is made.
    private let client: JellyfinServerClient
    @State private var sessionManager: SessionManager

    init() {
        let client = JellyfinServerClient(identity: .current())
        self.client = client
        _sessionManager = State(
            initialValue: SessionManager(
                store: MediaServerStore(storage: KeychainStorage(service: Self.keychainService)),
                authority: client
            )
        )
    }

    private static var keychainService: String {
        #if DEBUG
        // UI tests pass a fresh service name so every launch starts signed out.
        if let override = ProcessInfo.processInfo.environment["PORTFOLIO_KEYCHAIN_SERVICE"] {
            return override
        }
        #endif
        return Bundle.main.bundleIdentifier ?? "Portfolio"
    }

    var body: some Scene {
        WindowGroup {
            RootView(sessionManager: sessionManager, client: client) { profiles in
                ProfilesView(viewModel: profiles)
            } main: { currentProfile in
                MainNavigationView(currentProfile: currentProfile)
            }
        }
    }
}
