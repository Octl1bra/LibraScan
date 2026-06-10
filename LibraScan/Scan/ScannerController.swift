//
//  ScannerController.swift
//  LibraScan
//

@preconcurrency import AVFoundation
import Combine
import Foundation

struct ScanPayload: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let symbology: String
}

@MainActor
final class ScannerController: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var isCameraUnavailable = false
    @Published private(set) var isTorchAvailable = false
    @Published private(set) var isTorchOn = false
    @Published private(set) var zoomFactor: CGFloat = 1

    private var minZoom: CGFloat = 1
    private var maxZoom: CGFloat = 1
    /// Most recent scan, shown as a transient banner; scanning continues uninterrupted.
    @Published var latestScan: ScanPayload?

    nonisolated(unsafe) let session = AVCaptureSession()

    private nonisolated let sessionQueue = DispatchQueue(label: "com.Libra.LibraScan.sessionQueue")

    // Touched only on sessionQueue.
    private nonisolated(unsafe) var isConfigured = false
    private nonisolated(unsafe) var configurationFailed = false

    private var videoDevice: AVCaptureDevice?

    /// UI intent: true between start() and stop(). Gates interruption-recovery so the
    /// camera never restarts while the scan screen is not the active surface.
    private var wantsRunning = false

    /// Per-content sliding dedup windows. Keyed by content (not a single last-scan
    /// slot) so two codes alternating in frame don't break each other's window and
    /// spam the banner and history.
    private var recentScans: [String: Date] = [:]
    private let dedupWindow: TimeInterval = 0.5

    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        let token = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.wantsRunning else { return }
                self.start()
            }
        }
        observers.append(token)
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func requestAccessIfNeeded() async {
        guard authorizationStatus == .notDetermined else { return }
        _ = await AVCaptureDevice.requestAccess(for: .video)
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    }

    func start() {
        wantsRunning = true
        guard authorizationStatus == .authorized else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureIfNeeded()
            guard self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        wantsRunning = false
        // The system turns the torch off when the session stops; mirror that in UI state.
        isTorchOn = false
        sessionQueue.async { [weak self] in
            // Unconditional: an interrupted session is already auto-stopped (isRunning
            // is false), but only an explicit stopRunning() cancels the preserved run
            // request — otherwise AVFoundation restarts the camera when the
            // interruption ends, even with the scan screen inactive.
            self?.session.stopRunning()
        }
    }

    func toggleTorch() {
        guard let device = videoDevice, device.hasTorch else { return }
        // Optimistic update so rapid taps alternate instead of reading a stale value;
        // reverted only if the hardware refuses the change.
        let turnOn = !isTorchOn
        isTorchOn = turnOn
        sessionQueue.async { [weak self] in
            do {
                try device.lockForConfiguration()
                device.torchMode = turnOn ? .on : .off
                device.unlockForConfiguration()
            } catch {
                guard let self else { return }
                Task { @MainActor in
                    self.isTorchOn = !turnOn
                }
            }
        }
    }

    func setZoom(_ factor: CGFloat) {
        guard let device = videoDevice else { return }
        let clamped = min(max(factor, minZoom), maxZoom)
        guard abs(clamped - zoomFactor) > 0.001 else { return }
        // Optimistic, same as the torch: the gesture reads zoomFactor as its anchor,
        // so it must reflect the requested value immediately.
        zoomFactor = clamped
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {}
        }
    }

    // Runs on sessionQueue.
    private nonisolated func configureIfNeeded() {
        guard !isConfigured, !configurationFailed else { return }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device)
        else {
            configurationFailed = true
            Task { @MainActor in self.isCameraUnavailable = true }
            return
        }

        session.beginConfiguration()
        let output = AVCaptureMetadataOutput()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            configurationFailed = true
            Task { @MainActor in self.isCameraUnavailable = true }
            return
        }
        session.addInput(input)
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        let wanted: [AVMetadataObject.ObjectType] = [
            .qr, .dataMatrix, .aztec, .pdf417,
            .ean13, .ean8, .upce,
            .code39, .code93, .code128, .itf14, .codabar,
        ]
        output.metadataObjectTypes = wanted.filter(output.availableMetadataObjectTypes.contains)
        session.commitConfiguration()
        isConfigured = true

        let torchAvailable = device.hasTorch
        let minZoomFactor = device.minAvailableVideoZoomFactor
        // Digital zoom beyond ~8x is useless noise for code scanning.
        let maxZoomFactor = min(device.maxAvailableVideoZoomFactor, 8)
        let currentZoom = device.videoZoomFactor
        Task { @MainActor in
            self.videoDevice = device
            self.isTorchAvailable = torchAvailable
            self.minZoom = minZoomFactor
            self.maxZoom = maxZoomFactor
            self.zoomFactor = currentZoom
        }
    }
}

// Delegate callbacks are delivered on the main queue (see setMetadataObjectsDelegate).
extension ScannerController: @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let code = metadataObjects
            .compactMap({ $0 as? AVMetadataMachineReadableCodeObject })
            .first(where: { $0.stringValue?.isEmpty == false }),
            let content = code.stringValue
        else { return }

        let now = Date()
        if recentScans.count > 64 {
            recentScans = recentScans.filter { now.timeIntervalSince($0.value) < dedupWindow }
        }
        let lastSeen = recentScans[content]
        // Always refresh: the window keeps sliding while a code stays in frame,
        // so it only re-fires after being out of view for the full window.
        recentScans[content] = now
        if let lastSeen, now.timeIntervalSince(lastSeen) < dedupWindow {
            return
        }
        latestScan = ScanPayload(content: content, symbology: code.type.displayName)
    }
}

extension AVMetadataObject.ObjectType {
    nonisolated var displayName: String {
        switch self {
        case .qr: "QR Code"
        case .dataMatrix: "Data Matrix"
        case .aztec: "Aztec"
        case .pdf417: "PDF417"
        case .ean13: "EAN-13"
        case .ean8: "EAN-8"
        case .upce: "UPC-E"
        case .code39: "Code 39"
        case .code93: "Code 93"
        case .code128: "Code 128"
        case .itf14: "ITF-14"
        case .codabar: "Codabar"
        default: rawValue.components(separatedBy: ".").last ?? rawValue
        }
    }
}
