//
//  LibraScanMacApp.swift
//  LibraScan for Mac
//

import AppKit
import SwiftUI

@main
struct LibraScanMacApp: App {
    @NSApplicationDelegateAdaptor(ReopenDelegate.self) private var reopenDelegate
    @StateObject private var server = BridgeServer()
    @StateObject private var updates = UpdateChecker()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(server: server, updates: updates)
        } label: {
            StatusIconLabel(server: server)
                .task { updates.checkIfDue() }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(server: server, updates: updates)
        }
    }
}

/// Launching the already-running app again (Finder / Launchpad / Dock) is the
/// only "open" gesture an agent app has besides its menu bar icon — treat it
/// as "show me the app" and bring up Settings.
final class ReopenDelegate: NSObject, NSApplicationDelegate {
    private(set) static weak var shared: ReopenDelegate?

    /// The official open-Settings action, captured from the SwiftUI
    /// environment by StatusIconLabel (alive from launch).
    var openSettings: (() -> Void)?

    override init() {
        super.init()
        Self.shared = self
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Same activation dance as the menu's Settings… button: without it the
        // window opens behind the focused app.
        NSApp.activate(ignoringOtherApps: true)
        openSettings?()
        return false
    }
}

struct StatusIconLabel: View {
    @ObservedObject var server: BridgeServer
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(systemName: iconName)
            .onAppear {
                let openSettings = openSettings
                ReopenDelegate.shared?.openSettings = { openSettings() }
            }
    }

    private var iconName: String {
        if server.isPaused {
            "keyboard.slash"
        } else if server.connectedPeerName != nil {
            "keyboard.fill"
        } else {
            "keyboard"
        }
    }
}
