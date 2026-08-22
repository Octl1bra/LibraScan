#if DEBUG
import Foundation
import SwiftData

/// Deterministic App Store screenshot data and routing.
///
/// Nothing in this file exists in Release builds, and Debug builds still need
/// the explicit `-LibraScanDemoMode` launch argument before it does anything.
enum LibraScanDemoMode {
    enum Screen: String {
        case scan
        case history
        case bridge
    }

    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-LibraScanDemoMode")

    static let screen: Screen = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let keyIndex = arguments.firstIndex(of: "-LibraScanDemoScreen"),
              arguments.indices.contains(keyIndex + 1)
        else { return .scan }
        return Screen(rawValue: arguments[keyIndex + 1]) ?? .scan
    }()

    static let macName = "Libra 的 MacBook Pro"
    static let scanPayload = ScanPayload(
        content: "https://scan.libra.wiki",
        symbology: "QR Code"
    )

    @MainActor
    static func seed(_ container: ModelContainer) {
        guard isEnabled else { return }

        let context = ModelContext(container)
        do {
            let calendar = Calendar(identifier: .gregorian)
            let now = Date()
            let samples: [(String, String, DateComponents)] = [
                ("6901234567892", "EAN-13", .init(minute: -7)),
                ("https://scan.libra.wiki", "QR Code", .init(hour: -1, minute: -18)),
                ("SN-LS-2026-0819-A7", "Code 128", .init(hour: -3, minute: -42)),
                ("9787115428028", "EAN-13", .init(hour: -6, minute: -5)),
                ("PKG-CN-8842-19", "Code 128", .init(day: -1, hour: -2)),
                ("https://libra.wiki/support", "QR Code", .init(day: -1, hour: -7, minute: -24)),
                ("4710088490127", "EAN-13", .init(day: -2, hour: 2, minute: -11)),
            ]

            for (content, symbology, offset) in samples {
                let scannedAt = calendar.date(byAdding: offset, to: now) ?? now
                context.insert(ScanRecord(content: content, symbology: symbology, scannedAt: scannedAt))
            }
            try context.save()
        } catch {
            assertionFailure("Unable to seed screenshot demo records: \(error)")
        }
    }
}
#endif
