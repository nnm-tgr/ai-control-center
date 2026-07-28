//
//  AIControlCenterApp.swift
//  AIControlCenter
//
//  Created by daxe_ishihara on 2026/07/28.
//

import SwiftUI

@main
struct AIControlCenterApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
        .defaultSize(width: 1100, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
