//
//  HapticFeedback.swift
//  LibraScan
//

import UIKit

enum HapticFeedback {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
