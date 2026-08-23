//
//  ScreenWakeKeeper.swift
//  LibraScan
//

import UIKit

/// Holds off auto-lock for a while after each scan, then hands the idle timer
/// back to the system.
///
/// Neither extreme is right here. Letting the screen lock mid-session is
/// expensive: it drops the Multipeer link to the Mac and costs an unlock before
/// the next code. But pinning the screen awake for as long as the scan tab is
/// open is worse — the app sits on a counter all afternoon draining the battery
/// while nobody is scanning. So the screen stays awake only while scanning is
/// actually happening, and a user who walks away gets their own Auto-Lock
/// setting back within the minute.
@MainActor
final class ScreenWakeKeeper {
    /// Long enough to cover picking up the next box, short enough that walking
    /// away restores normal behaviour promptly.
    private let window: Duration = .seconds(60)
    private var release: Task<Void, Never>?

    /// Call after each scan.
    func extend() {
        UIApplication.shared.isIdleTimerDisabled = true
        release?.cancel()
        release = Task { [window] in
            try? await Task.sleep(for: window)
            guard !Task.isCancelled else { return }
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    /// Call when the scan screen stops being the thing the user is looking at —
    /// another tab, the background, teardown. Holding the idle timer past that
    /// point is a battery leak the user can't see or explain.
    func stop() {
        release?.cancel()
        release = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    deinit {
        // The task holds no reference to self, so cancelling here is not enough;
        // clear the flag directly rather than leaving it set for good.
        MainActor.assumeIsolated { UIApplication.shared.isIdleTimerDisabled = false }
    }
}
