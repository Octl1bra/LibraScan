//
//  UpdateChecker.swift
//  LibraScan for Mac
//

import AppKit
import Combine
import Foundation

enum UpdateKeys {
    static let automatic = "automaticUpdateChecks"
    static let lastCheck = "lastUpdateCheck"
}

/// Asks scan.libra.wiki whether a newer build exists.
///
/// macOS has no first-party updater for apps distributed with a Developer ID:
/// Apple's answer is the Mac App Store, and Sparkle is the community standard.
/// LibraScan ships no third-party SDKs, so this is the smallest thing that does
/// the job — one unparameterised GET, a build-number comparison, and a link to
/// the download page. It never downloads or installs anything, and it sends
/// nothing about the device or how the app is used.
@MainActor
final class UpdateChecker: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL)
        case failed
    }

    @Published private(set) var status: Status = .idle

    private static let feedURL = URL(string: "https://scan.libra.wiki/appcast.json")!
    private static let interval: TimeInterval = 24 * 60 * 60

    private struct Feed: Decodable {
        let version: String
        let build: Int
        let url: URL
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    init() {
        UserDefaults.standard.register(defaults: [UpdateKeys.automatic: true])
    }

    /// Launch and menu-open path: respects the user's setting and checks at most
    /// once a day. The Settings button calls `check()` directly instead.
    func checkIfDue() {
        guard UserDefaults.standard.bool(forKey: UpdateKeys.automatic) else { return }
        if let last = UserDefaults.standard.object(forKey: UpdateKeys.lastCheck) as? Date,
           Date.now.timeIntervalSince(last) < Self.interval {
            return
        }
        Task { await check() }
    }

    func check() async {
        guard status != .checking else { return }
        status = .checking
        UserDefaults.standard.set(Date.now, forKey: UpdateKeys.lastCheck)

        var request = URLRequest(url: Self.feedURL)
        // The download page is edge-cached; never answer from a stale local copy.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                status = .failed
                return
            }
            let feed = try JSONDecoder().decode(Feed.self, from: data)
            let installed = Int(currentBuild) ?? 0
            status = feed.build > installed
                ? .available(version: feed.version, url: feed.url)
                : .upToDate
        } catch {
            // Offline, DNS, malformed feed — all the same to the user: try later.
            status = .failed
        }
    }

    /// Hands the download to the browser. Installing stays a deliberate act:
    /// an app that types keystrokes should never replace itself unattended.
    func openDownloadPage() {
        if case .available(_, let url) = status {
            NSWorkspace.shared.open(url)
        }
    }
}
