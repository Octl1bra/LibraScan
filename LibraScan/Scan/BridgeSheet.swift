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

    var body: some View {
        NavigationStack {
            Form {
                switch bridge.state {
                case .connected(let macName):
                    connectedSection(macName: macName)
                case .connecting(let macName):
                    connectingSection(macName: macName)
                default:
                    nearbyMacsSection
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
        .onAppear { bridge.sheetOpened() }
        .onDisappear { bridge.sheetClosed() }
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
