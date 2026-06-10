//
//  BridgeServer.swift
//  ScanKeyboard
//

import AppKit
import Combine
import Foundation
@preconcurrency import MultipeerConnectivity

struct TypedItem: Identifiable {
    let id = UUID()
    let content: String
    let typed: Bool
    let date: Date
}

struct TrustedPeer: Identifiable {
    var id: String { name }
    let name: String
    let pairedAt: Date
}

enum SettingsKeys {
    static let suffix = "typingSuffix"
    static let delayMs = "typingDelayMs"
    static let autoAcceptTrusted = "autoAcceptTrusted"
    static let trustedPeers = "trustedPeers"
}

/// Advertises the `librascan-key` service, accepts one iPhone at a time,
/// and turns incoming scan messages into synthesized keystrokes.
@MainActor
final class BridgeServer: NSObject, ObservableObject {
    static let serviceType = "librascan-key"

    @Published private(set) var isAdvertising = false
    @Published private(set) var connectedPeerName: String?
    @Published private(set) var recentItems: [TypedItem] = []
    @Published private(set) var trustedPeers: [TrustedPeer] = []
    @Published private(set) var isAccessibilityTrusted = AXIsProcessTrusted()
    @Published var isPaused = false {
        didSet { typingEngine.setPaused(isPaused) }
    }

    private let localPeerID = MCPeerID(displayName: Host.current().localizedName ?? "Mac")
    private let typingEngine = TypingEngine()
    private var advertiser: MCNearbyServiceAdvertiser?
    /// The one session we consider authoritative. Any callback from a different
    /// MCSession object is from a losing/orphaned invitation and is dropped.
    private var session: MCSession?

    /// seq -> wasTyped. Duplicate deliveries (in-flight resend) are acked with
    /// the recorded outcome instead of being typed again. Reset per connection.
    private var handledSeqs: [Int: Bool] = [:]
    private var handledOrder: [Int] = []
    private let handledSeqLimit = 64

    private var heartbeatTask: Task<Void, Never>?
    private var missedPongs = 0

    override init() {
        UserDefaults.standard.register(defaults: [
            SettingsKeys.suffix: TypingSuffix.returnKey.rawValue,
            SettingsKeys.delayMs: 3.0,
            SettingsKeys.autoAcceptTrusted: true,
        ])
        super.init()
        trustedPeers = Self.loadTrustedPeers()
        startAdvertising()
    }

    // MARK: - Advertising / session lifecycle

    private func startAdvertising() {
        guard advertiser == nil else { return }
        let advertiser = MCNearbyServiceAdvertiser(
            peer: localPeerID,
            discoveryInfo: nil,
            serviceType: Self.serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
        isAdvertising = true
    }

    private func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        isAdvertising = false
    }

    func disconnect() {
        session?.disconnect()
    }

    private func tearDownSession() {
        connectedPeerName = nil
        session = nil
        handledSeqs.removeAll()
        handledOrder.removeAll()
        stopHeartbeat()
        startAdvertising()
    }

    // MARK: - Accessibility permission

    func refreshAccessibility() {
        isAccessibilityTrusted = AXIsProcessTrusted()
    }

    func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        isAccessibilityTrusted = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Trust list

    private static func loadTrustedPeers() -> [TrustedPeer] {
        let dict = UserDefaults.standard.dictionary(forKey: SettingsKeys.trustedPeers) as? [String: Date] ?? [:]
        return dict
            .map { TrustedPeer(name: $0.key, pairedAt: $0.value) }
            .sorted { $0.pairedAt < $1.pairedAt }
    }

    private func saveTrustedPeers() {
        let dict = Dictionary(uniqueKeysWithValues: trustedPeers.map { ($0.name, $0.pairedAt) })
        UserDefaults.standard.set(dict, forKey: SettingsKeys.trustedPeers)
    }

    func removeTrustedPeer(_ name: String) {
        trustedPeers.removeAll { $0.name == name }
        saveTrustedPeers()
    }

    private func addTrustedPeer(_ name: String) {
        guard !trustedPeers.contains(where: { $0.name == name }) else { return }
        trustedPeers.append(TrustedPeer(name: name, pairedAt: .now))
        saveTrustedPeers()
    }

    private func isTrusted(_ name: String) -> Bool {
        trustedPeers.contains { $0.name == name }
    }

    // MARK: - Invitations

    private func handleInvitation(from peer: MCPeerID, handler: @escaping (Bool, MCSession?) -> Void) {
        // One session at a time, tracked from the moment we accept (not from
        // .connected) so invitations arriving during the handshake are rejected.
        guard session == nil else {
            handler(false, nil)
            return
        }

        let autoAccept = UserDefaults.standard.bool(forKey: SettingsKeys.autoAcceptTrusted)
        if isTrusted(peer.displayName), autoAccept {
            accept(peer, handler: handler)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Allow “\(peer.displayName)” to connect?")
        alert.informativeText = String(
            localized: "Codes scanned on this iPhone will be typed into whatever text field has focus on this Mac."
        )
        alert.addButton(withTitle: String(localized: "Allow"))
        alert.addButton(withTitle: String(localized: "Don’t Allow"))

        // A second invitation could arrive while this modal is up; only accept if
        // we are still free.
        let allowed = alert.runModal() == .alertFirstButtonReturn
        guard session == nil else {
            handler(false, nil)
            return
        }
        if allowed {
            addTrustedPeer(peer.displayName)
            accept(peer, handler: handler)
        } else {
            handler(false, nil)
        }
    }

    private func accept(_ peer: MCPeerID, handler: (Bool, MCSession?) -> Void) {
        let session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session
        // Stop advertising as soon as we commit to a peer, closing the window in
        // which a second invitation could be accepted.
        stopAdvertising()
        handler(true, session)
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()
        missedPongs = 0
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !Task.isCancelled, self.session != nil else { return }
                if self.missedPongs >= 2 {
                    self.disconnect()
                    return
                }
                self.missedPongs += 1
                self.send(BridgeMessage(type: BridgeMessage.Kind.ping))
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    // MARK: - Messages

    private func handle(_ message: BridgeMessage) {
        // Any traffic proves the peer is alive.
        missedPongs = 0

        guard message.v <= BridgeMessage.currentVersion else {
            send(BridgeMessage(type: BridgeMessage.Kind.unsupported))
            return
        }

        switch message.type {
        case BridgeMessage.Kind.scan:
            handleScan(message)
        case BridgeMessage.Kind.ping:
            send(BridgeMessage(type: BridgeMessage.Kind.pong))
        case BridgeMessage.Kind.ack, BridgeMessage.Kind.pong, BridgeMessage.Kind.unsupported:
            break
        default:
            send(BridgeMessage(type: BridgeMessage.Kind.unsupported))
        }
    }

    private func handleScan(_ message: BridgeMessage) {
        guard let content = message.content, let seq = message.seq else { return }

        if let wasTyped = handledSeqs[seq] {
            // Already seen on this connection (in-flight resend) — echo the
            // recorded outcome rather than typing again.
            sendAck(seq: seq, typed: wasTyped)
            return
        }

        refreshAccessibility()
        guard isAccessibilityTrusted else {
            appendRecent(content: content, typed: false)
            sendAck(seq: seq, typed: false, reason: "no-permission")
            promptForAccessibility()
            return
        }
        guard !isPaused else {
            appendRecent(content: content, typed: false)
            sendAck(seq: seq, typed: false, reason: "paused")
            return
        }

        // Record before typing (placeholder false) so an in-flight resend of the
        // same seq doesn't double-type; the real outcome overwrites it.
        recordSeq(seq, typed: false)

        let suffix = TypingSuffix(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.suffix) ?? "")
            ?? .returnKey
        let delayMs = UserDefaults.standard.double(forKey: SettingsKeys.delayMs)
        typingEngine.type(content, suffix: suffix, delayMs: delayMs) { [weak self] outcome in
            guard let self else { return }
            let typed = outcome == .typed
            self.recordSeq(seq, typed: typed)
            self.appendRecent(content: content, typed: typed)
            self.sendAck(seq: seq, typed: typed, reason: typed ? nil : Self.reason(for: outcome))
        }
    }

    private static func reason(for outcome: TypingOutcome) -> String? {
        switch outcome {
        case .typed: nil
        case .paused: "paused"
        case .noPermission: "no-permission"
        case .failed: "typing-failed"
        }
    }

    private func recordSeq(_ seq: Int, typed: Bool) {
        if handledSeqs[seq] == nil {
            handledOrder.append(seq)
            if handledOrder.count > handledSeqLimit {
                let evicted = handledOrder.removeFirst()
                handledSeqs[evicted] = nil
            }
        }
        handledSeqs[seq] = typed
    }

    private func appendRecent(content: String, typed: Bool) {
        recentItems.insert(TypedItem(content: content, typed: typed, date: .now), at: 0)
        if recentItems.count > 5 {
            recentItems.removeLast(recentItems.count - 5)
        }
    }

    private func sendAck(seq: Int, typed: Bool, reason: String? = nil) {
        send(BridgeMessage(type: BridgeMessage.Kind.ack, seq: seq, typed: typed, reason: reason))
    }

    private func send(_ message: BridgeMessage) {
        guard let session, !session.connectedPeers.isEmpty,
              let data = try? message.encoded()
        else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension BridgeServer: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        Task { @MainActor in
            self.handleInvitation(from: peerID, handler: invitationHandler)
        }
    }
}

// MARK: - MCSessionDelegate

extension BridgeServer: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            // Ignore callbacks from any session other than the authoritative one;
            // a losing invitation's session must not mutate our state or keep typing.
            guard session === self.session else {
                if state == .connected { session.disconnect() }
                return
            }
            switch state {
            case .connected:
                self.connectedPeerName = peerID.displayName
                self.stopAdvertising()
                self.startHeartbeat()
            case .notConnected:
                self.tearDownSession()
            default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? BridgeMessage.decode(data) else { return }
        Task { @MainActor in
            guard session === self.session else { return }
            self.handle(message)
        }
    }

    nonisolated func session(
        _ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID
    ) {}

    nonisolated func session(
        _ session: MCSession, didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID, with progress: Progress
    ) {}

    nonisolated func session(
        _ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?
    ) {}
}
