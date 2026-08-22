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

/// Asks GitHub whether a newer release exists.
///
/// macOS has no first-party updater for apps distributed with a Developer ID:
/// Apple's answer is the Mac App Store, and Sparkle is the community standard.
/// LibraScan ships no third-party SDKs, so this is the smallest thing that does
/// the job — one request, a version comparison, and a link. It never downloads
/// or installs anything, and it sends nothing about the device or how the app
/// is used.
///
/// Reading the releases API rather than a file on scan.libra.wiki means a
/// release is complete the moment the tag finishes building: there is no second
/// place holding a version number that could disagree with the first.
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

    /// The repository publishes both `mac-v*` and `ios-v*` tags, so "latest
    /// release" is not specific enough — this asks for the list and picks the
    /// newest Mac one.
    private static let releasesURL = URL(
        string: "https://api.github.com/repos/Octl1bra/LibraScan/releases?per_page=20"
    )!
    private static let tagPrefix = "mac-v"
    private static let assetName = "LibraScan.dmg"
    private static let interval: TimeInterval = 24 * 60 * 60

    private struct Release: Decodable {
        let tagName: String
        let htmlUrl: URL
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
        }
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

    /// Launch path: respects the user's setting and checks at most once a day.
    /// The Settings button calls `check()` directly instead.
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

        var request = URLRequest(url: Self.releasesURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        // GitHub rejects requests without one; identify the app, nothing about the user.
        request.setValue("LibraScan/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                status = .failed
                return
            }
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let releases = try decoder.decode([Release].self, from: data)

            guard let newest = releases.first(where: {
                !$0.draft && !$0.prerelease && $0.tagName.hasPrefix(Self.tagPrefix)
            }) else {
                status = .upToDate
                return
            }

            let version = String(newest.tagName.dropFirst(Self.tagPrefix.count))
            guard Self.isNewer(version, than: currentVersion) else {
                status = .upToDate
                return
            }
            let asset = newest.assets.first { $0.name == Self.assetName }
            status = .available(version: version, url: asset?.browserDownloadUrl ?? newest.htmlUrl)
        } catch {
            // Offline, rate-limited, malformed — all the same to the user: try later.
            status = .failed
        }
    }

    /// Compares dotted numeric versions component by component, so 1.10 sorts
    /// above 1.9 rather than below it the way a string compare would have it.
    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = installed.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let l = i < a.count ? a[i] : 0
            let r = i < b.count ? b[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// Hands the download to the browser. Installing stays a deliberate act:
    /// an app that types keystrokes should never replace itself unattended.
    func openDownloadPage() {
        if case .available(_, let url) = status {
            NSWorkspace.shared.open(url)
        }
    }
}
