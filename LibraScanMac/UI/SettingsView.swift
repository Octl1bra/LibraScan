//
//  SettingsView.swift
//  LibraScan for Mac
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var server: BridgeServer

    @AppStorage(SettingsKeys.suffix) private var suffix = TypingSuffix.returnKey.rawValue
    @AppStorage(SettingsKeys.delayMs) private var delayMs = 3.0
    @AppStorage(SettingsKeys.autoAcceptTrusted) private var autoAccept = true

    var body: some View {
        Form {
            Section {
                Picker("After typing a code", selection: $suffix) {
                    Text("Do nothing").tag(TypingSuffix.none.rawValue)
                    Text("Press Return").tag(TypingSuffix.returnKey.rawValue)
                    Text("Press Tab").tag(TypingSuffix.tab.rawValue)
                }
                HStack {
                    Slider(value: $delayMs, in: 1...20, step: 1) {
                        Text("Keystroke interval")
                    }
                    Text("\(Int(delayMs)) ms")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
            }

            Section {
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
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove") {
                                server.removeTrustedPeer(peer.name)
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 340)
    }
}
