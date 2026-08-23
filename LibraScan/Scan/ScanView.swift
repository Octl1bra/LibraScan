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
    @State private var screenWake = ScreenWakeKeeper()

    private let bannerDuration: Duration = .seconds(4)

    var body: some View {
        ZStack {
            scanSurface
        }
        .task {
#if DEBUG
            if LibraScanDemoMode.isEnabled {
                scanner.latestScan = LibraScanDemoMode.scanPayload
                bridge.send(LibraScanDemoMode.scanPayload, scannedAt: .now)
                if LibraScanDemoMode.screen == .bridge {
                    await Task.yield()
                    isBridgeSheetPresented = true
                }
                return
            }
#endif
            await scanner.requestAccessIfNeeded()
            if isActive {
                scanner.start()
            }
        }
        .onChange(of: isActive) { _, active in
#if DEBUG
            if LibraScanDemoMode.isEnabled { return }
#endif
            if active {
                scanner.start()
            } else {
                scanner.stop()
                screenWake.stop()
            }
        }
        .onChange(of: scenePhase) { _, phase in
#if DEBUG
            if LibraScanDemoMode.isEnabled { return }
#endif
            switch phase {
            case .active:
                if isActive {
                    scanner.start()
                }
                bridge.sceneDidBecomeActive()
            case .background:
                scanner.stop()
                screenWake.stop()
                bridge.sceneDidEnterBackground()
            default:
                break
            }
        }
        .onChange(of: scanner.latestScan) { _, payload in
            guard let payload else { return }
#if DEBUG
            if LibraScanDemoMode.isEnabled {
                bridge.send(payload, scannedAt: .now)
                return
            }
#endif
            HapticFeedback.success()
            screenWake.extend()
            let record = ScanRecord(content: payload.content, symbology: payload.symbology)
            modelContext.insert(record)
            // History is the source of truth; the Mac bridge is a side channel.
            bridge.send(payload, scannedAt: record.scannedAt)
            scheduleBannerDismiss(for: payload)
        }
        .sheet(isPresented: $isBridgeSheetPresented) {
            BridgeSheet(bridge: bridge)
        }
        .onDisappear { screenWake.stop() }
    }

    @ViewBuilder
    private var scanSurface: some View {
#if DEBUG
        if LibraScanDemoMode.isEnabled {
            cameraView
        } else {
            regularScanSurface
        }
#else
        regularScanSurface
#endif
    }

    @ViewBuilder
    private var regularScanSurface: some View {
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
#if DEBUG
            if LibraScanDemoMode.isEnabled {
                DemoCameraPreview()
                    .ignoresSafeArea()
            } else {
                ScannerPreview(session: scanner.session)
                    .ignoresSafeArea()
            }
#else
            ScannerPreview(session: scanner.session)
                .ignoresSafeArea()
#endif

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

#if DEBUG
/// A screenshot-only simulator stand-in for the unavailable camera feed.
/// The capture script supplies a complete desk-and-QR image only to its Debug
/// build; it is not a target resource.
private struct DemoCameraPreview: View {
    private let backgroundImage: UIImage? = {
        guard let url = Bundle.main.url(
            forResource: "demo-camera-background",
            withExtension: "png"
        ) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }()

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let backgroundImage {
                    Image(uiImage: backgroundImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    Color(red: 0.055, green: 0.063, blue: 0.075)
                }

                // A slight camera-style exposure reduction keeps the white
                // viewfinder and guidance readable over the desk photo.
                Color.black.opacity(0.13)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

}
#endif

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
