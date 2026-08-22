//
//  BridgeSheet.swift
//  LibraScan
//

import MultipeerConnectivity
import SwiftUI

/// Connection panel for the Mac keyboard bridge: nearby Mac list, connection
/// status, resend toggle and disconnect.
struct BridgeSheet: View {
    @ObservedObject var bridge: BridgeClient

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// Where the free Mac app comes from. Half of this feature lives on a
    /// machine the user may not have set up yet, so the panel has to be able to
    /// send them there rather than just saying no Macs were found.
    private static let macAppURL = URL(string: "https://scan.libra.wiki")!

    var body: some View {
        NavigationStack {
            Form {
                if let incompatibility = bridge.incompatibility {
                    incompatibilitySection(incompatibility)
                }

                switch bridge.state {
                case .connected(let macName):
                    connectedSection(macName: macName)
                case .connecting(let macName):
                    connectingSection(macName: macName)
                default:
                    nearbyMacsSection
                    getMacAppSection
                }

                queueSection

                if bridge.wantsConnection {
                    Section {
                        Button("Disconnect", role: .destructive) {
                            bridge.disconnect()
                        }
                    }
                }
            }
            .navigationTitle("Type to Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        // At the medium detent the camera is still running behind the top half
        // of the screen. A glass sheet lets that moving image through and makes
        // the list of Macs hard to read, so this one is opaque.
        .presentationBackground(Color(.systemGroupedBackground))
        .onAppear { bridge.sheetOpened() }
        .onDisappear { bridge.sheetClosed() }
    }

    /// A protocol-version mismatch keeps the link up but makes every scan fail,
    /// so say which side is behind rather than repeating "failed" per scan.
    private func incompatibilitySection(_ incompatibility: BridgeIncompatibility) -> some View {
        Section {
            Label {
                switch incompatibility {
                case .macIsOlder:
                    Text("LibraScan on the Mac is too old to understand this iPhone.")
                case .appIsOlder:
                    Text("This app is too old to understand LibraScan on the Mac.")
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            if incompatibility == .macIsOlder {
                Link("Download the latest Mac app", destination: Self.macAppURL)
            }
        } footer: {
            Text("Scans can't be typed until both sides are updated.")
        }
    }

    private func connectedSection(macName: String) -> some View {
        Section {
            HStack {
                Label(macName, systemImage: "desktopcomputer")
                Spacer()
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
                    .foregroundStyle(.green)
            }
        } footer: {
            Text("Scanned codes are typed into whatever text field has focus on the Mac.")
        }
    }

    private func connectingSection(macName: String) -> some View {
        Section {
            HStack {
                Label(macName, systemImage: "desktopcomputer")
                Spacer()
                ProgressView()
            }
        } footer: {
            Text("Connecting… Accept the request on the Mac if it asks.")
        }
    }

    private var nearbyMacsSection: some View {
        Section {
            if bridge.didBrowseFail {
                Label("Can't search for nearby Macs", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            } else if bridge.nearbyMacs.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Looking for nearby Macs…")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(bridge.nearbyMacs, id: \.self) { peer in
                    Button {
                        bridge.connect(to: peer)
                    } label: {
                        Label(peer.displayName, systemImage: "desktopcomputer")
                    }
                }
            }
        } header: {
            Text("Nearby Macs")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if bridge.didLastAttemptFail {
                    Text("Couldn't connect. Check that the Mac allowed the connection.")
                        .foregroundStyle(.red)
                }
                if bridge.wantsConnection, let lastMac = bridge.lastMacName {
                    Text("Will automatically reconnect to “\(lastMac)”.")
                }
                Text("Make sure Wi-Fi and Bluetooth are on for both devices, and LibraScan is running on the Mac.")
                if bridge.didBrowseFail || bridge.nearbyMacs.isEmpty {
                    Text("If no Macs appear, check that LibraScan is allowed to use the Local Network in Settings.")
                }
            }
        }
    }

    /// Shown whenever no Mac is connected: an empty list reads as "something is
    /// broken", when for a first-time user it usually just means the other half
    /// isn't installed.
    private var getMacAppSection: some View {
        Section {
            Link(destination: Self.macAppURL) {
                Label("Get LibraScan for Mac", systemImage: "arrow.down.circle")
            }
        } footer: {
            Text("Typing needs the free Mac app. Download it at scan.libra.wiki, then open it on your Mac — it lives in the menu bar.")
        }
    }

    private var queueSection: some View {
        Section {
            Toggle("Resend queued scans after reconnecting", isOn: $bridge.resendOnReconnect)
            if bridge.pendingCount > 0 {
                LabeledContent("Queued to send") {
                    Text(bridge.pendingCount, format: .number)
                }
            }
        }
    }
}

#Preview {
    BridgeSheet(bridge: BridgeClient())
}
