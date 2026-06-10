//
//  ScanResultBanner.swift
//  LibraScan
//

import SwiftUI

/// Transient, non-blocking result banner shown at the top of the scan screen.
/// Scanning keeps running while it is visible; it auto-hides from ScanView.
struct ScanResultBanner: View {
    let payload: ScanPayload

    @Environment(\.openURL) private var openURL
    @State private var copied = false

    private var url: URL? {
        ContentClassifier.url(in: payload.content)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                SymbologyTag(name: payload.symbology)
                Text(payload.content)
                    .font(.subheadline)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if let url {
                actionButton(systemImage: "safari", label: Text("Open Link")) {
                    openURL(url)
                }
            }
            actionButton(
                systemImage: copied ? "checkmark" : "doc.on.doc",
                label: copied ? Text("Copied") : Text("Copy")
            ) {
                copy()
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func actionButton(
        systemImage: String,
        label: Text,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .frame(width: 40, height: 40)
                .background(.quaternary, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func copy() {
        UIPasteboard.general.string = payload.content
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

struct SymbologyTag: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.tint.opacity(0.12), in: Capsule())
            .foregroundStyle(.tint)
    }
}

#Preview {
    VStack(spacing: 16) {
        ScanResultBanner(payload: ScanPayload(content: "https://example.com/some/long/path", symbology: "QR Code"))
        ScanResultBanner(payload: ScanPayload(content: "6901234567892", symbology: "EAN-13"))
    }
    .frame(maxHeight: .infinity)
    .background(.black)
}
