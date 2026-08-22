//
//  MenuContentView.swift
//  LibraScan for Mac
//

import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var server: BridgeServer
    @ObservedObject var updates: UpdateChecker
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow

            if !server.isAccessibilityTrusted {
                permissionWarning
            }

            if let incompatibility = server.incompatibility {
                incompatibilityWarning(incompatibility)
            }

            if case .available(let version, _) = updates.status {
                updateAvailableRow(version)
            }

            Toggle("Pause typing", isOn: $server.isPaused)
                .toggleStyle(.switch)
                .controlSize(.small)

            Divider()

            recentSection

            Divider()

            HStack {
                Button("Settings…") {
                    // An LSUIElement agent app must activate itself, otherwise the
                    // Settings window opens behind the focused app.
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 300)
        .onAppear {
            server.refreshAccessibility()
            updates.checkIfDue()
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(server.connectedPeerName != nil ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            if let name = server.connectedPeerName {
                Text("Connected to \(name)")
                    .font(.headline)
            } else {
                Text("Waiting for iPhone…")
                    .font(.headline)
            }
            Spacer()
            if server.connectedPeerName != nil {
                Button("Disconnect") {
                    server.disconnect()
                }
                .controlSize(.small)
            }
        }
    }

    private var permissionWarning: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Accessibility permission is required to type.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Button("Grant Permission…") {
                server.promptForAccessibility()
                if let url = URL(
                    string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                ) {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func updateAvailableRow(_ version: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
            Text("Version \(version) is available.")
                .font(.caption)
            Spacer()
            Button("Get") { updates.openDownloadPage() }
                .controlSize(.small)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    /// Mirrors the iPhone's warning: the link is up but nothing can be typed
    /// until whichever side is behind gets updated.
    private func incompatibilityWarning(_ incompatibility: PeerIncompatibility) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                switch incompatibility {
                case .appIsOlder:
                    Text("This app is too old to understand the iPhone.")
                case .peerIsOlder:
                    Text("LibraScan on the iPhone is too old to understand this Mac.")
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption)
            .foregroundStyle(.orange)
            Text("Scans can't be typed until both sides are updated.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent")
                .font(.caption)
                .foregroundStyle(.secondary)
            if server.recentItems.isEmpty {
                Text("Nothing typed yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(server.recentItems) { item in
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.content, forType: .string)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.typed ? "checkmark.circle.fill" : "exclamationmark.circle")
                                .foregroundStyle(item.typed ? .green : .orange)
                            Text(item.content)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .help(Text("Click to copy"))
                }
            }
        }
    }
}
