//
//  ScanResultSheet.swift
//  LibraScan
//

import SwiftUI

struct ScanResultSheet: View {
    let payload: ScanPayload

    @Environment(\.openURL) private var openURL
    @State private var copied = false

    private var url: URL? {
        ContentClassifier.url(in: payload.content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Scan Result")
                    .font(.headline)
                Spacer()
                SymbologyTag(name: payload.symbology)
            }

            ScrollView {
                Text(payload.content)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 130)

            VStack(spacing: 10) {
                if let url {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Open Link", systemImage: "safari")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    HStack(spacing: 10) {
                        copyButton(prominent: false)
                        shareButton
                    }
                } else {
                    copyButton(prominent: true)
                    shareButton
                }
            }
            .controlSize(.large)
        }
        .padding(20)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
    }

    private func copyButton(prominent: Bool) -> some View {
        Button {
            copy()
        } label: {
            Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(AnyPrimitiveButtonStyle(prominent: prominent))
    }

    private var shareButton: some View {
        ShareLink(item: payload.content) {
            Label("Share", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
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

/// Type-erasing wrapper so the copy button can switch between bordered styles.
private struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        if prominent {
            Button(configuration).buttonStyle(.borderedProminent)
        } else {
            Button(configuration).buttonStyle(.bordered)
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
    Color.black.sheet(isPresented: .constant(true)) {
        ScanResultSheet(payload: ScanPayload(content: "https://example.com", symbology: "QR Code"))
    }
}
