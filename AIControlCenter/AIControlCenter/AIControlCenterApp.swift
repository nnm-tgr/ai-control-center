//
//  AIControlCenterApp.swift
//  AIControlCenter
//
//  Created by daxe_ishihara on 2026/07/28.
//

import SwiftUI

@main
struct AIControlCenterApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environment(appState)
                .task { await appState.start() }
        }
        .defaultSize(width: 1100, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        SwiftUI.Settings {
            SettingsView()
                .environment(appState)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            MenuBarIconLabel()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)
    }
}
