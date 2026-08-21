//
//  BridgeMessage.swift
//  ScanKeyboard
//
//  Wire protocol shared with the iOS LibraScan app.
//  Keep in sync with docs/MAC_KEY_BRIDGE.md in the LibraScan repo.
//

import Foundation

nonisolated struct BridgeMessage: Codable {
    /// Message kinds are plain strings so unknown future kinds decode fine
    /// and can be answered with `unsupported` instead of failing.
    enum Kind {
        static let scan = "scan"
        static let ack = "ack"
        static let ping = "ping"
        static let pong = "pong"
        static let unsupported = "unsupported"
    }

    static let currentVersion = 1

    var v: Int = BridgeMessage.currentVersion
    var type: String
    var seq: Int?
    var content: String?
    var symbology: String?
    var scannedAt: Date?
    var typed: Bool?
    var reason: String?

    static func decode(_ data: Data) throws -> BridgeMessage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BridgeMessage.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
