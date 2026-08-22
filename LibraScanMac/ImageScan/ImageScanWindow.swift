//
//  ImageScanWindow.swift
//  LibraScan for Mac
//

import AppKit
import Combine
import SwiftUI

/// Results of the most recent "scan these files" request.
@MainActor
final class ImageScanStore: ObservableObject {
    @Published private(set) var results: [ImageScanResult] = []
    /// Set when exactly one code was found and it went straight to the clipboard,
    /// which is the common case: one screenshot, one QR code, nothing to choose.
    @Published private(set) var autoCopied: String?

    var allCodes: [ImageScanResult.Code] { results.flatMap { $0.codes ?? [] } }

    func scan(_ urls: [URL]) {
        let found = ImageCodeScanner.scan(urls: urls)
        results = found
        let codes = found.flatMap { $0.codes ?? [] }
        if codes.count == 1 {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(codes[0].content, forType: .string)
            autoCopied = codes[0].content
        } else {
            autoCopied = nil
        }
    }
}

struct ImageScanResultsView: View {
    @ObservedObject var store: ImageScanStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.results.isEmpty {
                ContentUnavailableView("No Images Scanned", systemImage: "photo")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.results) { result in
                        Section(result.url.lastPathComponent) {
                            if let codes = result.codes {
                                if codes.isEmpty {
                                    Text("No code found in this image.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(codes) { code in
                                        CodeRow(code: code)
                                    }
                                }
                            } else {
                                Text("Couldn't read this file as an image.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            if let copied = store.autoCopied {
                Divider()
                Label("Copied “\(copied)” to the clipboard.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(12)
            }
        }
        .frame(minWidth: 460, minHeight: 260)
    }
}

private struct CodeRow: View {
    let code: ImageScanResult.Code
    @State private var copied = false
    @Environment(\.openURL) private var openURL

    private var url: URL? {
        let t = code.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.lowercased().hasPrefix("http://") || t.lowercased().hasPrefix("https://") else { return nil }
        return URL(string: t)
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(code.content)
                    .textSelection(.enabled)
                    .lineLimit(3)
                Text(code.symbology)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if let url {
                Button("Open") { openURL(url) }
            }
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code.content, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// A plain AppKit window. An agent app has no window scene to piggyback on, and
/// driving SwiftUI's scene plumbing from an app delegate is more machinery than
/// one results panel is worth.
@MainActor
final class ImageScanWindowController {
    static let shared = ImageScanWindowController()

    let store = ImageScanStore()
    private var window: NSWindow?

    func show(urls: [URL]) {
        store.scan(urls)

        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = String(localized: "Scan Results")
            w.isReleasedWhenClosed = false
            w.center()
            w.contentView = NSHostingView(rootView: ImageScanResultsView(store: store))
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
