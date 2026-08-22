//
//  TypingEngine.swift
//  LibraScan for Mac
//

import ApplicationServices
import CoreGraphics
import Foundation
import os

nonisolated enum TypingSuffix: String, CaseIterable {
    case none
    case returnKey = "return"
    case tab
    case space

    fileprivate var virtualKey: CGKeyCode? {
        switch self {
        case .none: nil
        case .returnKey: 36  // kVK_Return
        case .tab: 48        // kVK_Tab
        case .space: 49      // kVK_Space
        }
    }
}

nonisolated enum TypingOutcome {
    case typed
    case paused
    case noPermission
    case failed
}

/// Synthesizes keyboard events via CGEvent. Unicode is written directly into
/// the events (no key-map lookup), so any text — CJK, emoji — types correctly
/// regardless of the active keyboard layout. All jobs run on one serial queue
/// so back-to-back scans come out in order.
final class TypingEngine {
    /// CGEvent carries at most 20 UTF-16 code units per keyboard event.
    private nonisolated static let chunkSize = 20

    private nonisolated let queue = DispatchQueue(label: "com.Libra.Scan.typing")
    /// Read on the typing queue before/while typing so a pause takes effect even
    /// for jobs already queued or a long payload mid-flight.
    private nonisolated let pausedFlag = OSAllocatedUnfairLock(initialState: false)

    nonisolated func setPaused(_ paused: Bool) {
        pausedFlag.withLock { $0 = paused }
    }

    func type(
        _ text: String,
        suffix: TypingSuffix,
        delayMs: Double,
        completion: @escaping @MainActor (TypingOutcome) -> Void
    ) {
        let paused = pausedFlag
        queue.async {
            let outcome = Self.typeNow(text, suffix: suffix, delayMs: delayMs, paused: paused)
            Task { @MainActor in
                completion(outcome)
            }
        }
    }

    // Runs on `queue`.
    private nonisolated static func typeNow(
        _ text: String,
        suffix: TypingSuffix,
        delayMs: Double,
        paused: OSAllocatedUnfairLock<Bool>
    ) -> TypingOutcome {
        if paused.withLock({ $0 }) { return .paused }
        // Re-check at type time (not just enqueue time): permission can be revoked
        // while jobs sit in the queue.
        guard AXIsProcessTrusted() else { return .noPermission }
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return .failed }

        let delay = UInt32(max(0, delayMs) * 1000)
        let units = Array(text.utf16)

        var index = 0
        while index < units.count {
            if paused.withLock({ $0 }) { return .paused }
            var end = min(index + chunkSize, units.count)
            // Never split a surrogate pair across two events.
            if end < units.count, UTF16.isLeadSurrogate(units[end - 1]) {
                end -= 1
            }
            postUnicode(Array(units[index..<end]), source: source)
            if delay > 0 { usleep(delay) }
            index = end
        }

        if let key = suffix.virtualKey {
            postKey(key, source: source)
            if delay > 0 { usleep(delay) }
        }
        return .typed
    }

    private nonisolated static func postUnicode(_ chunk: [UniChar], source: CGEventSource) {
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else { continue }
            chunk.withUnsafeBufferPointer { buffer in
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: buffer.baseAddress)
            }
            // Clear inherited modifier flags so a scan arriving while the user holds
            // ⌘ isn't dispatched as a shortcut (e.g. ⌘+content turning into ⌘Q).
            event.flags = []
            event.post(tap: .cghidEventTap)
        }
    }

    private nonisolated static func postKey(_ key: CGKeyCode, source: CGEventSource) {
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: keyDown) else { continue }
            event.flags = []
            event.post(tap: .cghidEventTap)
        }
    }
}
