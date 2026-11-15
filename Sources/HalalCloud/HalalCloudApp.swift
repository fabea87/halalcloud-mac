//
//  HalalCloudApp.swift
//  HalalCloud
//

import AppKit
import SwiftUI

@main
@MainActor
struct HalalCloudApp: App {

    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window(AppInfo.displayName, id: "main") {
            RootView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        // Stands in for the Qt system tray icon of the Windows client.
        MenuBarExtra {
            Button("Show \(AppInfo.displayName)") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("Quit \(AppInfo.displayName)") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: "cloud.fill")
        }
    }
}
