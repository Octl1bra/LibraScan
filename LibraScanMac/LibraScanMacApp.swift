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
                .task {
                    updates.checkIfDue()
                    // The user grants Accessibility in System Settings, outside
                    // this app; in `.menu` style there is no reliable onAppear
                    // to notice on, so watch for it while it is still missing.
                    while !Task.isCancelled, !server.isAccessibilityTrusted {
                        try? await Task.sleep(for: .seconds(2))
                        server.refreshAccessibility()
                    }
                }
        }
        // A real AppKit menu, not a window: the system supplies row metrics,
        // the shortcut column, vibrancy and highlighting for free, and no
        // hand-drawn approximation of those ever quite matches.
        .menuBarExtraStyle(.menu)

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Makes the Services entry ("Scan Codes with LibraScan") reach us.
        NSApp.servicesProvider = self
    }

    /// Finder's Open With, a drop on the icon, or `open -a`. Each path lands here.
    func application(_ application: NSApplication, open urls: [URL]) {
        ImageScanWindowController.shared.show(urls: urls)
    }

    /// The Services menu hands files over on a pasteboard instead.
    @objc func scanImages(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? []
        guard !urls.isEmpty else {
            error.pointee = String(localized: "No image files were provided.") as NSString
            return
        }
        ImageScanWindowController.shared.show(urls: urls)
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

    /// "keyboard.slash" does not exist in SF Symbols — asking for it rendered
    /// nothing at all, so pausing made the menu bar icon vanish. Pause is the
    /// emergency stop; it has to stay visible and obviously different.
    private var iconName: String {
        if server.isPaused {
            "pause.fill"
        } else if server.connectedPeerName != nil {
            "keyboard.fill"
        } else {
            "keyboard"
        }
    }
}
