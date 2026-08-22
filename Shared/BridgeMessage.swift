//
//  BridgeMessage.swift
//  LibraScan (Shared)
//
//  Wire protocol between LibraScan for iOS (BridgeClient) and LibraScan for Mac
//  (BridgeServer). One file, compiled into both targets.
//

import Foundation

nonisolated struct BridgeMessage: Codable {
    /// Message kinds are plain strings so unknown future kinds decode fine
    /// and can be answered with `unsupported` instead of failing.
    ///
    /// An `unsupported` reply echoes the rejected message's `seq` when it had
    /// one, so the sender can settle that exact scan rather than leaving it in
    /// flight. Older builds simply ignore the extra field.
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
