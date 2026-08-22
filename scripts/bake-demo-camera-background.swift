#!/usr/bin/env swift

import AppKit
import CoreImage
import Foundation

guard CommandLine.arguments.count == 4 else {
    fputs("usage: bake-demo-camera-background.swift <source.png> <output.png> <payload>\n", stderr)
    exit(64)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let payload = CommandLine.arguments[3]

guard let background = CIImage(contentsOf: sourceURL) else {
    fputs("Could not load source image: \(sourceURL.path)\n", stderr)
    exit(66)
}

let generator = CIFilter(name: "CIQRCodeGenerator")!
generator.setValue(Data(payload.utf8), forKey: "inputMessage")
generator.setValue("M", forKey: "inputCorrectionLevel")
guard let qrCode = generator.outputImage else {
    fputs("Could not generate QR code\n", stderr)
    exit(70)
}

// Keep the paper visible through the ink so the result reads as a printed
// label rather than a UI image pasted on top of the camera preview.
let ink = CIFilter(name: "CIFalseColor")!
ink.setValue(qrCode, forKey: kCIInputImageKey)
ink.setValue(CIColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 0.9), forKey: "inputColor0")
ink.setValue(CIColor(red: 1, green: 1, blue: 1, alpha: 0), forKey: "inputColor1")

guard let inkImage = ink.outputImage else {
    fputs("Could not color QR code\n", stderr)
    exit(70)
}

let width = background.extent.width
let height = background.extent.height
let perspective = CIFilter(name: "CIPerspectiveTransform")!
perspective.setValue(inkImage, forKey: kCIInputImageKey)
perspective.setValue(CIVector(x: width * 0.399, y: height * 0.592), forKey: "inputTopLeft")
perspective.setValue(CIVector(x: width * 0.629, y: height * 0.555), forKey: "inputTopRight")
perspective.setValue(CIVector(x: width * 0.566, y: height * 0.393), forKey: "inputBottomRight")
perspective.setValue(CIVector(x: width * 0.322, y: height * 0.438), forKey: "inputBottomLeft")

guard let printedCode = perspective.outputImage else {
    fputs("Could not apply QR perspective\n", stderr)
    exit(70)
}

let result = printedCode.composited(over: background).cropped(to: background.extent)
let context = CIContext()
guard let cgImage = context.createCGImage(
    result,
    from: background.extent,
    format: .RGBA8,
    colorSpace: CGColorSpaceCreateDeviceRGB()
),
      let pngData = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
else {
    fputs("Could not render output image; background=\(background.extent), qr=\(qrCode.extent), printed=\(printedCode.extent), result=\(result.extent)\n", stderr)
    exit(70)
}

do {
    try pngData.write(to: outputURL, options: .atomic)
} catch {
    fputs("Could not write output image: \(error)\n", stderr)
    exit(74)
}
