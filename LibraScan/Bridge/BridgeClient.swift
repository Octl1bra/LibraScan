//
//  BridgeClient.swift
//  LibraScan
//

import Combine
import Foundation
@preconcurrency import MultipeerConnectivity
import UIKit

/// Delivery status of one scanned payload pushed over the bridge, keyed by
/// `ScanPayload.id` and surfaced as a badge on the result banner.
enum BridgeDelivery: Equatable {
    /// Bridge is on but offline; waiting in the pending queue.
    case queued
    /// Handed to the session; waiting for the Mac's ack.
    case sent
    /// The Mac confirmed it typed the content.
    case typed
    /// Ack with `typed: false` (reason supplied by the Mac) or a transport
    /// failure / dropped queue entry (reason `nil`).
    case failed(reason: String?)
}

enum BridgeState: Equatable {
    case off
    case browsing
    case connecting(macName: String)
    case connected(macName: String)
}

/// iOS side of the Mac keyboard bridge: browses for the `librascan-key`
/// service advertised by LibraScan for Mac, pushes scans over an encrypted
/// MCSession, and tracks per-payload delivery from the Mac's acks.
/// Scans always land in local history first — the bridge is a side channel.
@MainActor
final class BridgeClient: NSObject, ObservableObject {
    /// Must match `BridgeServer.serviceType` in LibraScanMac/Bridge/BridgeServer.swift.
    static let serviceType = "librascan-key"

    @Published private(set) var state: BridgeState = .off
    @Published private(set) var nearbyMacs: [MCPeerID] = []
    /// True from the moment the user picks a Mac until they explicitly
    /// disconnect. Gates sending, queueing and auto-reconnect.
    @Published private(set) var wantsConnection = false
    @Published private(set) var pendingCount = 0
    /// Set when an invitation ends without connecting (declined / timed out),
    /// so the sheet can explain instead of silently returning to the list.
    @Published private(set) var didLastAttemptFail = false
    /// Set when the browser reports it could not start at all (most commonly
    /// Local Network permission denied); cleared when browsing restarts.
    @Published private(set) var didBrowseFail = false
    /// payloadID -> delivery, pruned in insertion order.
    @Published private(set) var deliveries: [UUID: BridgeDelivery] = [:]
    @Published var resendOnReconnect: Bool {
        didSet { UserDefaults.standard.set(resendOnReconnect, forKey: Self.resendKey) }
    }

    var isConnected: Bool {
        if case .connected = state { return true }
        return false
    }

    var lastMacName: String? {
        UserDefaults.standard.string(forKey: Self.lastMacKey)
    }

    private static let resendKey = "bridgeResendOnReconnect"
    private static let lastMacKey = "bridgeLastMacName"
    private static let peerSuffixKey = "bridgePeerNameSuffix"

    private let localPeerID = BridgeClient.makeLocalPeerID()

    /// Without the user-assigned-device-name entitlement, `UIDevice.current.name`
    /// is just the model name ("iPhone") on device. The Mac keys its consent
    /// dialog and trust list on this string, so a generic name would make every
    /// LibraScan iPhone interchangeable there (trust one, trust all).
    /// Disambiguate with a stable per-install suffix.
    private static func makeLocalPeerID() -> MCPeerID {
        let name = UIDevice.current.name
        guard name == UIDevice.current.model else {
            return MCPeerID(displayName: name)
        }
        let suffix: String
        if let stored = UserDefaults.standard.string(forKey: peerSuffixKey) {
            suffix = stored
        } else {
            suffix = String(UUID().uuidString.prefix(4))
            UserDefaults.standard.set(suffix, forKey: peerSuffixKey)
        }
        return MCPeerID(displayName: "\(name) (\(suffix))")
    }
    private var browser: MCNearbyServiceBrowser?
    /// The one session we consider authoritative. Any callback from a different
    /// MCSession object is from an abandoned attempt and is dropped.
    private var session: MCSession?

    private var isSheetOpen = false
    private var isInBackground = false

    private struct PendingScan {
        let payloadID: UUID
        let content: String
        let symbology: String
        let scannedAt: Date
    }

    /// Scans made while the bridge is on but offline (§4.4 of the design doc).
    private var pendingQueue: [PendingScan] = [] {
        didSet { pendingCount = pendingQueue.count }
    }
    private let pendingLimit = 50

    private var nextSeq = 1
    /// seq -> payload id of scans sent and not yet acked.
    private var inFlight: [Int: UUID] = [:]
    private var deliveryOrder: [UUID] = []
    private let deliveryLimit = 64

    private var heartbeatTask: Task<Void, Never>?
    private var missedPongs = 0

    override init() {
        UserDefaults.standard.register(defaults: [Self.resendKey: true])
        resendOnReconnect = UserDefaults.standard.bool(forKey: Self.resendKey)
        super.init()
    }

    // MARK: - User actions

    func sheetOpened() {
        isSheetOpen = true
        didLastAttemptFail = false
        updateBrowsing()
    }

    func sheetClosed() {
        isSheetOpen = false
        updateBrowsing()
    }

    func connect(to peer: MCPeerID) {
        guard session == nil, let browser else { return }
        didLastAttemptFail = false
        wantsConnection = true
        UserDefaults.standard.set(peer.displayName, forKey: Self.lastMacKey)
        let session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session
        state = .connecting(macName: peer.displayName)
        // The Mac shows a consent dialog on first contact; give it the full
        // default window before the invitation times out.
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 30)
    }

    func disconnect() {
        wantsConnection = false
        // Turning the bridge off intentionally abandons anything queued for it.
        failPendingQueue()
        if let session {
            // Tear down immediately: a session still mid-handshake may never
            // deliver .notConnected, and a late callback for this session is
            // ignored via the === guard.
            session.disconnect()
            tearDownSession()
        } else {
            state = isSheetOpen ? .browsing : .off
            updateBrowsing()
        }
    }

    // MARK: - Scene lifecycle

    func sceneDidEnterBackground() {
        isInBackground = true
        // Multipeer sessions don't survive backgrounding; dropping explicitly
        // is the documented behavior. wantsConnection stays set so we
        // reconnect on return.
        if let session {
            session.disconnect()
            tearDownSession()
        } else {
            updateBrowsing()
        }
    }

    func sceneDidBecomeActive() {
        isInBackground = false
        updateBrowsing()
    }

    // MARK: - Sending scans

    func send(_ payload: ScanPayload, scannedAt: Date) {
        guard wantsConnection else { return }
        let scan = PendingScan(
            payloadID: payload.id,
            content: payload.content,
            symbology: payload.symbology,
            scannedAt: scannedAt
        )
        if isConnected {
            transmit(scan)
        } else {
            enqueue(scan)
        }
    }

    private func enqueue(_ scan: PendingScan) {
        pendingQueue.append(scan)
        if pendingQueue.count > pendingLimit {
            let dropped = pendingQueue.removeFirst()
            recordDelivery(.failed(reason: nil), for: dropped.payloadID)
        }
        recordDelivery(.queued, for: scan.payloadID)
    }

    private func transmit(_ scan: PendingScan) {
        guard let session, !session.connectedPeers.isEmpty else {
            enqueue(scan)
            return
        }
        let seq = nextSeq
        nextSeq += 1
        let message = BridgeMessage(
            type: BridgeMessage.Kind.scan,
            seq: seq,
            content: scan.content,
            symbology: scan.symbology,
            scannedAt: scan.scannedAt
        )
        do {
            try session.send(message.encoded(), toPeers: session.connectedPeers, with: .reliable)
            inFlight[seq] = scan.payloadID
            recordDelivery(.sent, for: scan.payloadID)
        } catch {
            // The session is going away; keep the scan for the next connection.
            enqueue(scan)
        }
    }

    private func flushPendingQueue() {
        guard !pendingQueue.isEmpty else { return }
        guard resendOnReconnect else {
            failPendingQueue()
            return
        }
        let queued = pendingQueue
        pendingQueue.removeAll()
        for scan in queued {
            transmit(scan)
        }
    }

    private func failPendingQueue() {
        for scan in pendingQueue {
            recordDelivery(.failed(reason: nil), for: scan.payloadID)
        }
        pendingQueue.removeAll()
    }

    private func recordDelivery(_ delivery: BridgeDelivery, for payloadID: UUID) {
        if deliveries[payloadID] == nil {
            deliveryOrder.append(payloadID)
            if deliveryOrder.count > deliveryLimit {
                deliveries[deliveryOrder.removeFirst()] = nil
            }
        }
        deliveries[payloadID] = delivery
    }

    // MARK: - Browsing

    private func updateBrowsing() {
        let shouldBrowse = !isInBackground && !isConnected && (isSheetOpen || wantsConnection)
        if shouldBrowse {
            startBrowsing()
        } else {
            stopBrowsing()
        }
    }

    private func startBrowsing() {
        guard browser == nil else { return }
        didBrowseFail = false
        let browser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
        if state == .off {
            state = .browsing
        }
    }

    private func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
        nearbyMacs = []
        if state == .browsing, !wantsConnection {
            state = .off
        }
    }

    private func handleFound(_ peer: MCPeerID) {
        if !nearbyMacs.contains(peer) {
            nearbyMacs.append(peer)
            nearbyMacs.sort {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }
        // Auto-reconnect: the bridge is on but lost its Mac (background, sleep,
        // drop); re-invite as soon as it reappears, sheet open or not.
        if wantsConnection, session == nil, peer.displayName == lastMacName {
            connect(to: peer)
        }
    }

    private func handleLost(_ peer: MCPeerID) {
        nearbyMacs.removeAll { $0 == peer }
    }

    // MARK: - Session lifecycle

    private func handleConnected(to peerName: String) {
        didLastAttemptFail = false
        state = .connected(macName: peerName)
        startHeartbeat()
        updateBrowsing()
        flushPendingQueue()
    }

    private func tearDownSession() {
        // An invitation that ends without connecting (declined / timed out /
        // cancelled) is a failed pairing, not a dropped link: there is nothing
        // to "reconnect" to, and silently re-inviting would re-pop the Mac's
        // consent dialog. Reset the intent and let the user retry explicitly.
        // Report it only if the user still wanted the bridge — not when they
        // cancelled it themselves or the app is heading to the background.
        let wasConnecting = if case .connecting = state { true } else { false }
        if wasConnecting {
            didLastAttemptFail = wantsConnection && !isInBackground
            wantsConnection = false
            failPendingQueue()
        }

        session = nil
        stopHeartbeat()
        // Sent-but-unacked scans are NOT requeued: the Mac's seq dedup resets
        // per connection, so resending could double-type into a document. The
        // content is already in local history; mark it failed instead.
        for payloadID in inFlight.values {
            recordDelivery(.failed(reason: nil), for: payloadID)
        }
        inFlight.removeAll()

        state = (wantsConnection || isSheetOpen) ? .browsing : .off
        updateBrowsing()
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()
        missedPongs = 0
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !Task.isCancelled, let session = self.session else { return }
                if self.missedPongs >= 2 {
                    // Same deterministic teardown as disconnect(): don't depend
                    // on a .notConnected callback for a link we know is dead.
                    session.disconnect()
                    self.tearDownSession()
                    return
                }
                self.missedPongs += 1
                self.sendControl(BridgeMessage(type: BridgeMessage.Kind.ping))
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
            sendControl(BridgeMessage(type: BridgeMessage.Kind.unsupported))
            return
        }

        switch message.type {
        case BridgeMessage.Kind.ack:
            handleAck(message)
        case BridgeMessage.Kind.ping:
            sendControl(BridgeMessage(type: BridgeMessage.Kind.pong))
        case BridgeMessage.Kind.pong, BridgeMessage.Kind.unsupported:
            break
        default:
            sendControl(BridgeMessage(type: BridgeMessage.Kind.unsupported))
        }
    }

    private func handleAck(_ message: BridgeMessage) {
        guard let seq = message.seq,
              let payloadID = inFlight.removeValue(forKey: seq)
        else { return }
        if message.typed == true {
            recordDelivery(.typed, for: payloadID)
        } else {
            recordDelivery(.failed(reason: message.reason), for: payloadID)
        }
    }

    private func sendControl(_ message: BridgeMessage) {
        guard let session, !session.connectedPeers.isEmpty,
              let data = try? message.encoded()
        else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension BridgeClient: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        Task { @MainActor in
            guard browser === self.browser else { return }
            self.handleFound(peerID)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            guard browser === self.browser else { return }
            self.handleLost(peerID)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: any Error) {
        Task { @MainActor in
            guard browser === self.browser else { return }
            self.didBrowseFail = true
        }
    }
}

// MARK: - MCSessionDelegate

extension BridgeClient: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            // Ignore callbacks from any session other than the authoritative one.
            guard session === self.session else {
                if state == .connected { session.disconnect() }
                return
            }
            switch state {
            case .connected:
                self.handleConnected(to: peerID.displayName)
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
