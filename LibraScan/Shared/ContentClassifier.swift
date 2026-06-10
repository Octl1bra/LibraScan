//
//  ContentClassifier.swift
//  LibraScan
//

import Foundation

enum ContentClassifier {
    /// Returns an openable web URL if the scanned content is an http(s) link.
    static func url(in content: String) -> URL? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host() != nil
        else { return nil }
        return url
    }
}
