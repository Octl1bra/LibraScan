//
//  RecordsExport.swift
//  LibraScan
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Lazily renders all scan records into a plain-text file when the user
/// commits to a share destination, so building the ShareLink stays cheap.
nonisolated struct RecordsExport: Transferable {
    struct Row {
        let content: String
        let symbology: String
        let scannedAt: Date
    }

    let rows: [Row]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { export in
            SentTransferredFile(try export.writeToTemporaryFile())
        }
    }

    private func writeToTemporaryFile() throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let filename = "LibraScan Record \(formatter.string(from: .now)).txt"

        var text = ""
        for row in rows {
            text += "[\(formatter.string(from: row.scannedAt))] [\(row.symbology)]\n"
            text += row.content
            text += "\n\n"
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
