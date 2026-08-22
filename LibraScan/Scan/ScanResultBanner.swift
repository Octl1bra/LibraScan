//
//  ScanResultBanner.swift
//  LibraScan
//

import SwiftUI

/// Transient, non-blocking result banner shown at the top of the scan screen.
/// Scanning keeps running while it is visible; it auto-hides from ScanView.
struct ScanResultBanner: View {
    let payload: ScanPayload
    var delivery: BridgeDelivery?

    @Environment(\.openURL) private var openURL
    @State private var copied = false

    private var url: URL? {
        ContentClassifier.url(in: payload.content)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    SymbologyTag(name: payload.symbology)
                    if let delivery {
                        BridgeDeliveryBadge(delivery: delivery)
                    }
                }
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

/// Compact bridge status shown next to the symbology tag while the Mac
/// keyboard bridge is on, driven by the Mac's acks.
private struct BridgeDeliveryBadge: View {
    let delivery: BridgeDelivery

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private var text: LocalizedStringKey {
        switch delivery {
        case .queued: "Waiting to send to Mac"
        case .sent: "Sending to Mac…"
        case .typed: "Typed on Mac"
        case .failed(let reason):
            switch reason {
            case "no-permission": "Mac not authorized to type"
            case "paused": "Typing paused on Mac"
            case BridgeClient.versionMismatchReason: "Mac app is out of date"
            default: "Failed to type on Mac"
            }
        }
    }

    private var systemImage: String {
        switch delivery {
        case .queued: "tray.full"
        case .sent: "ellipsis.circle"
        case .typed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch delivery {
        case .queued, .sent: .secondary
        case .typed: .green
        case .failed: .orange
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
        ScanResultBanner(payload: ScanPayload(content: "6901234567892", symbology: "EAN-13"), delivery: .typed)
        ScanResultBanner(
            payload: ScanPayload(content: "SN-0042-AC", symbology: "Code 128"),
            delivery: .failed(reason: "no-permission")
        )
    }
    .frame(maxHeight: .infinity)
    .background(.black)
}
