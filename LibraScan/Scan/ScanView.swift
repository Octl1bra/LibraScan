//
//  ScanView.swift
//  LibraScan
//

import AVFoundation
import SwiftData
import SwiftUI

struct ScanView: View {
    let isActive: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var scanner = ScannerController()
    @StateObject private var bridge = BridgeClient()
    @GestureState private var pinchAnchor: CGFloat?
    @State private var bannerDismissTask: Task<Void, Never>?
    @State private var isBridgeSheetPresented = false

    private let bannerDuration: Duration = .seconds(4)

    var body: some View {
        ZStack {
            switch scanner.authorizationStatus {
            case .authorized:
                if scanner.isCameraUnavailable {
                    CameraUnavailableView()
                } else {
                    cameraView
                }
            case .denied, .restricted:
                PermissionDeniedView()
            default:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Requesting camera access…")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            await scanner.requestAccessIfNeeded()
            if isActive {
                scanner.start()
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                scanner.start()
            } else {
                scanner.stop()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if isActive {
                    scanner.start()
                }
                bridge.sceneDidBecomeActive()
            case .background:
                scanner.stop()
                bridge.sceneDidEnterBackground()
            default:
                break
            }
        }
        .onChange(of: scanner.latestScan) { _, payload in
            guard let payload else { return }
            HapticFeedback.success()
            let record = ScanRecord(content: payload.content, symbology: payload.symbology)
            modelContext.insert(record)
            // History is the source of truth; the Mac bridge is a side channel.
            bridge.send(payload, scannedAt: record.scannedAt)
            scheduleBannerDismiss(for: payload)
        }
        .sheet(isPresented: $isBridgeSheetPresented) {
            BridgeSheet(bridge: bridge)
        }
    }

    private func scheduleBannerDismiss(for payload: ScanPayload) {
        bannerDismissTask?.cancel()
        bannerDismissTask = Task {
            try? await Task.sleep(for: bannerDuration)
            guard !Task.isCancelled, scanner.latestScan?.id == payload.id else { return }
            scanner.latestScan = nil
        }
    }

    private var cameraView: some View {
        ZStack {
            ScannerPreview(session: scanner.session)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                RoundedRectangle(cornerRadius: 28)
                    .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                    .frame(width: 250, height: 250)
                Text("Align a QR code or barcode within the frame")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }

            VStack(spacing: 16) {
                Spacer()
                if scanner.zoomFactor > 1.01 {
                    zoomBadge
                }
                if scanner.isTorchAvailable {
                    torchButton
                }
            }
            .padding(.bottom, 32)

            VStack(spacing: 12) {
                HStack {
                    Spacer()
                    bridgeButton
                }
                .padding(.trailing, 16)
                if let payload = scanner.latestScan {
                    ScanResultBanner(payload: payload, delivery: bridge.deliveries[payload.id])
                        .id(payload.id)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .padding(.top, 8)
            .animation(.snappy, value: scanner.latestScan)
        }
        .contentShape(Rectangle())
        .gesture(zoomGesture)
    }

    private var zoomGesture: some Gesture {
        // The anchor must live in @GestureState: it resets on cancellation too
        // (result sheet presenting mid-pinch, backgrounding), whereas an @State
        // cleared in onEnded leaks a stale anchor — onEnded never fires when the
        // system cancels the gesture — and snaps zoom on the next pinch.
        MagnifyGesture()
            .updating($pinchAnchor) { value, anchor, _ in
                let base = anchor ?? scanner.zoomFactor
                anchor = base
                scanner.setZoom(base * value.magnification)
            }
    }

    private var zoomBadge: some View {
        Text(verbatim: String(format: "%.1f×", scanner.zoomFactor))
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.black.opacity(0.4), in: Capsule())
    }

    private var bridgeButton: some View {
        Button {
            isBridgeSheetPresented = true
        } label: {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.title3)
                .foregroundStyle(bridge.isConnected ? Color.accentColor : .white)
                .padding(12)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel(Text("Type to Mac"))
        .accessibilityValue(bridge.isConnected ? Text("Connected") : Text("Not connected"))
    }

    private var torchButton: some View {
        Button {
            scanner.toggleTorch()
        } label: {
            Image(systemName: scanner.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                .font(.title2)
                .foregroundStyle(scanner.isTorchOn ? .yellow : .white)
                .padding(18)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel(scanner.isTorchOn ? Text("Turn torch off") : Text("Turn torch on"))
    }
}

private struct PermissionDeniedView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label("Camera Access Needed", systemImage: "camera.fill")
        } description: {
            Text("LibraScan uses the camera to scan QR codes and barcodes. The camera feed is never saved or uploaded.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

private struct CameraUnavailableView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Camera Unavailable", systemImage: "video.slash")
        } description: {
            Text("This device's camera is unavailable, so scanning won't work here.")
        }
    }
}
