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
    /// Non-nil while a scan result card is presented; scanning is suppressed until it is dismissed.
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

    private var lastContent: String?
    private var lastScanDate = Date.distantPast
    private let dedupWindow: TimeInterval = 2

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
        Task { @MainActor in
            self.videoDevice = device
            self.isTorchAvailable = torchAvailable
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
        if latestScan != nil {
            // Result card is up: suppress new scans, but keep the dedup window sliding
            // for the code still in frame so dismissing the card doesn't instantly
            // re-record it. A different code is left untouched and fires right away.
            if content == lastContent {
                lastScanDate = now
            }
            return
        }
        if content == lastContent, now.timeIntervalSince(lastScanDate) < dedupWindow {
            // Keep the window sliding while the camera stays on the same code.
            lastScanDate = now
            return
        }
        lastContent = content
        lastScanDate = now
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
