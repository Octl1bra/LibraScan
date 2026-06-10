//
//  HistoryDetailView.swift
//  LibraScan
//

import SwiftUI

struct HistoryDetailView: View {
    let record: ScanRecord

    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    SymbologyTag(name: record.symbology)
                    Spacer()
                    Text(record.scannedAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(record.content)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(20)
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            if let url = record.url {
                Button {
                    openURL(url)
                } label: {
                    Label("Open Link", systemImage: "safari")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                HStack(spacing: 10) {
                    copyButton
                    shareButton
                }
            } else {
                copyButton
                    .buttonStyle(.borderedProminent)
                shareButton
            }
        }
        .controlSize(.large)
        .padding(20)
        .background(.bar)
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = record.content
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        } label: {
            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private var shareButton: some View {
        ShareLink(item: record.content) {
            Label("Share", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
}
