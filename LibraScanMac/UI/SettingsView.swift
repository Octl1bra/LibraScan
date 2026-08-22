//
//  SettingsView.swift
//  LibraScan for Mac
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var server: BridgeServer
    @ObservedObject var updates: UpdateChecker

    @AppStorage(SettingsKeys.suffix) private var suffix = TypingSuffix.returnKey.rawValue
    @AppStorage(SettingsKeys.delayMs) private var delayMs = 3.0
    @AppStorage(SettingsKeys.autoAcceptTrusted) private var autoAccept = true
    @AppStorage(UpdateKeys.automatic) private var automaticUpdates = true

    var body: some View {
        Form {
            Section("Typing") {
                Picker("After typing a code", selection: $suffix) {
                    Text("Do nothing").tag(TypingSuffix.none.rawValue)
                    Text("Press Return").tag(TypingSuffix.returnKey.rawValue)
                    Text("Press Tab").tag(TypingSuffix.tab.rawValue)
                    Text("Press Space").tag(TypingSuffix.space.rawValue)
                }
                // LabeledContent, not a hand-rolled HStack: this keeps the label
                // in the form's leading column, aligned with the picker above it.
                LabeledContent("Keystroke interval") {
                    HStack(spacing: 8) {
                        Slider(value: $delayMs, in: 1...20, step: 1)
                        Text("\(Int(delayMs)) ms")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 46, alignment: .trailing)
                    }
                }
            }

            Section("Connection") {
                Toggle("Automatically accept trusted devices", isOn: $autoAccept)
            }

            Section("Trusted devices") {
                if server.trustedPeers.isEmpty {
                    Text("No trusted devices yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(server.trustedPeers) { peer in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(peer.name)
                                Text(peer.pairedAt, format: .dateTime.year().month().day())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove") {
                                server.removeTrustedPeer(peer.name)
                            }
                        }
                    }
                }
            }
            aboutSection
        }
        .formStyle(.grouped)
        // Width fixed like a System Settings pane; height follows the content,
        // because the trusted-device list grows and shrinks.
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The two apps ship on their own schedules, so the version has to be
    /// visible somewhere — it's the first thing any support question needs.
    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version") {
                Text(verbatim: "\(updates.currentVersion) (\(updates.currentBuild))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Toggle("Check for updates automatically", isOn: $automaticUpdates)
            HStack {
                Button("Check Now") {
                    Task { await updates.check() }
                }
                .disabled(updates.status == .checking)
                Spacer()
                updateStatusLabel
            }
        }
    }

    @ViewBuilder
    private var updateStatusLabel: some View {
        switch updates.status {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView().controlSize(.small)
        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        case .available(let version, _):
            Button("Get \(version)") { updates.openDownloadPage() }
        case .failed:
            Label("Couldn't check", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}
