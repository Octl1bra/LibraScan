//
//  ScanKeyboardApp.swift
//  ScanKeyboard
//

import SwiftUI

@main
struct ScanKeyboardApp: App {
    @StateObject private var server = BridgeServer()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(server: server)
        } label: {
            StatusIconLabel(server: server)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(server: server)
        }
    }
}

struct StatusIconLabel: View {
    @ObservedObject var server: BridgeServer

    var body: some View {
        Image(systemName: iconName)
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
