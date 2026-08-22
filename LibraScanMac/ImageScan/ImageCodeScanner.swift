//
//  ImageCodeScanner.swift
//  LibraScan for Mac
//

import AppKit
import Vision

/// Everything found in one image file.
nonisolated struct ImageScanResult: Identifiable {
    let id = UUID()
    let url: URL
    /// nil when the file could not be read as an image at all.
    let codes: [Code]?

    nonisolated struct Code: Identifiable {
        let id = UUID()
        let content: String
        let symbology: String
    }
}

/// Finds QR codes and barcodes in still images with Vision.
///
/// The camera path on iOS uses AVFoundation because it works on a live feed;
/// for files, Vision's barcode detector covers the same symbologies and more,
/// and needs no session setup. Everything runs locally.
nonisolated enum ImageCodeScanner {
    static func scan(urls: [URL]) -> [ImageScanResult] {
        urls.map { url in
            guard let image = NSImage(contentsOf: url),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            else {
                return ImageScanResult(url: url, codes: nil)
            }
            let request = VNDetectBarcodesRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage)
            guard (try? handler.perform([request])) != nil else {
                return ImageScanResult(url: url, codes: nil)
            }
            let codes = (request.results ?? [])
                .compactMap { observation -> ImageScanResult.Code? in
                    guard let payload = observation.payloadStringValue, !payload.isEmpty else { return nil }
                    return ImageScanResult.Code(
                        content: payload,
                        symbology: displayName(for: observation.symbology)
                    )
                }
            // Vision reports one observation per detected code, but a stretched
            // or reflected code can come back twice with identical payloads.
            var seen = Set<String>()
            let unique = codes.filter { seen.insert($0.symbology + "\u{1}" + $0.content).inserted }
            return ImageScanResult(url: url, codes: unique)
        }
    }

    /// Same vocabulary as the iOS scanner, so history and results read alike.
    private static func displayName(for symbology: VNBarcodeSymbology) -> String {
        switch symbology {
        case .qr: "QR Code"
        case .microQR: "Micro QR"
        case .aztec: "Aztec"
        case .dataMatrix: "Data Matrix"
        case .pdf417, .microPDF417: "PDF417"
        case .ean13: "EAN-13"
        case .ean8: "EAN-8"
        case .upce: "UPC-E"
        case .code39, .code39Checksum, .code39FullASCII, .code39FullASCIIChecksum: "Code 39"
        case .code93, .code93i: "Code 93"
        case .code128: "Code 128"
        case .itf14: "ITF-14"
        case .i2of5, .i2of5Checksum: "ITF"
        case .codabar: "Codabar"
        case .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited: "GS1 DataBar"
        case .msiPlessey: "MSI Plessey"
        default: symbology.rawValue.replacingOccurrences(of: "VNBarcodeSymbology", with: "")
        }
    }
}
