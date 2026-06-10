//
//  ScanRecord.swift
//  LibraScan
//

import Foundation
import SwiftData

@Model
final class ScanRecord {
    var content: String
    var symbology: String
    var scannedAt: Date
    var isURL: Bool

    init(content: String, symbology: String, scannedAt: Date = .now) {
        self.content = content
        self.symbology = symbology
        self.scannedAt = scannedAt
        self.isURL = ContentClassifier.url(in: content) != nil
    }

    var url: URL? {
        ContentClassifier.url(in: content)
    }
}
