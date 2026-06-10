//
//  MenuContentView.swift
//  ScanKeyboard
//

import AppKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var server: BridgeServer
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow

            if !server.isAccessibilityTrusted {
                permissionWarning
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
