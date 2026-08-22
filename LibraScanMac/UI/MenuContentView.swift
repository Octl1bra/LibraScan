//
//  MenuContentView.swift
//  LibraScan for Mac
//

import AppKit
import SwiftUI

/// The menu bar menu.
///
/// This is a real AppKit menu (`MenuBarExtra` in `.menu` style), not a window
/// dressed up as one. A hand-built menu ends up subtly wrong in every dimension
/// that matters — row height, the shortcut column, vibrancy, the highlight —
/// because those come from the system rather than from the app. So the content
/// here uses only the vocabulary a menu already has: items, toggles that draw
/// their own checkmark, plain text for headings, and separators.
struct MenuContentView: View {
    @ObservedObject var server: BridgeServer
    @ObservedObject var updates: UpdateChecker
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // A bare Text becomes a disabled item, which is exactly its role here:
        // something to read, not something to click.
        if let name = server.connectedPeerName {
            Text("Connected to \(name)")
            Button("Disconnect") { server.disconnect() }
        } else {
            Text("Waiting for iPhone…")
        }

        Divider()

        if !server.isAccessibilityTrusted {
            Text("Accessibility permission is required to type.")
            Button("Grant Permission…") {
                server.promptForAccessibility()
                if let url = URL(
                    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                ) {
                    NSWorkspace.shared.open(url)
                }
            }
            Divider()
        }

        if let incompatibility = server.incompatibility {
            switch incompatibility {
            case .appIsOlder:
                Text("This app is too old to understand the iPhone.")
            case .peerIsOlder:
                Text("LibraScan on the iPhone is too old to understand this Mac.")
            }
            Text("Scans can't be typed until both sides are updated.")
            Divider()
        }

        if case .available(let version, _) = updates.status {
            Button("Download Version \(version)…") { updates.openDownloadPage() }
            Divider()
        }

        // A Toggle in a menu draws the system checkmark in the reserved left
        // column — the same thing Surge's "Set as System Proxy" row does.
        Toggle("Pause Typing", isOn: $server.isPaused)
            .keyboardShortcut("p")

        Divider()

        Text("Recent")
        if server.recentItems.isEmpty {
            Text("Nothing typed yet.")
        } else {
            ForEach(server.recentItems) { item in
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.content, forType: .string)
                } label: {
                    Label(
                        item.content,
                        systemImage: item.typed ? "checkmark.circle" : "exclamationmark.circle"
                    )
                }
            }
        }

        Divider()

        Button("Settings…") {
            // An LSUIElement agent app must activate itself, otherwise the
            // Settings window opens behind the focused app.
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")

        Button("Quit LibraScan") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
