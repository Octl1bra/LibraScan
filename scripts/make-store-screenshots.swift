#!/usr/bin/env swift
import AppKit
import Foundation

private let canvasSize = NSSize(width: 1320, height: 2868)
private let screenshotWidth: CGFloat = 1160
private let screenshotTop: CGFloat = 2350
private let cornerRadius: CGFloat = 64
private let titleFont = NSFont.systemFont(ofSize: 82, weight: .semibold)

private struct StoreShot {
    let inputName: String
    let outputName: String
    let title: String
}

private struct StoreLocale {
    let directory: String
    let shots: [StoreShot]
}

private let locales = [
    StoreLocale(directory: "zh-Hans", shots: [
        StoreShot(inputName: "01-scan.png", outputName: "01-scan.png", title: "iPhone 扫码，Mac 上键入"),
        StoreShot(inputName: "02-history.png", outputName: "02-history.png", title: "扫过的都在，可搜索、可导出"),
        StoreShot(inputName: "03-type-to-mac.png", outputName: "03-type-to-mac.png", title: "点对点直连，不经服务器"),
    ]),
    StoreLocale(directory: "en-US", shots: [
        StoreShot(inputName: "01-scan.png", outputName: "01-scan.png", title: "Scan on iPhone. Type on Mac."),
        StoreShot(inputName: "02-history.png", outputName: "02-history.png", title: "Search and export every scan"),
        StoreShot(inputName: "03-type-to-mac.png", outputName: "03-type-to-mac.png", title: "Peer to peer. No servers."),
    ]),
]

private func value(of variable: String, in css: String) throws -> String {
    let escaped = NSRegularExpression.escapedPattern(for: variable)
    let regex = try NSRegularExpression(pattern: "\(escaped)\\s*:\\s*(#[0-9a-fA-F]{6})")
    let range = NSRange(css.startIndex..<css.endIndex, in: css)
    guard let match = regex.firstMatch(in: css, range: range),
          let valueRange = Range(match.range(at: 1), in: css)
    else {
        throw NSError(domain: "StoreScreenshots", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Missing \(variable) in site/assets/style.css",
        ])
    }
    return String(css[valueRange])
}

private func color(hex: String) throws -> NSColor {
    guard hex.count == 7, let integer = Int(hex.dropFirst(), radix: 16) else {
        throw NSError(domain: "StoreScreenshots", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Invalid color: \(hex)",
        ])
    }
    return NSColor(
        calibratedRed: CGFloat((integer >> 16) & 0xff) / 255,
        green: CGFloat((integer >> 8) & 0xff) / 255,
        blue: CGFloat(integer & 0xff) / 255,
        alpha: 1
    )
}

private func render(
    shot: StoreShot,
    sourceURL: URL,
    outputURL: URL,
    paper: NSColor,
    ink: NSColor
) throws {
    guard let source = NSImage(contentsOf: sourceURL) else {
        throw NSError(domain: "StoreScreenshots", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Cannot read \(sourceURL.path)",
        ])
    }
    let screenshotHeight = screenshotWidth * source.size.height / source.size.width
    let screenshotRect = NSRect(
        x: (canvasSize.width - screenshotWidth) / 2,
        y: screenshotTop - screenshotHeight,
        width: screenshotWidth,
        height: screenshotHeight
    )
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width),
        pixelsHigh: Int(canvasSize.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "StoreScreenshots", code: 4)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    graphics.imageInterpolation = .high

    paper.setFill()
    NSRect(origin: .zero, size: canvasSize).fill()

    // Cast one restrained shadow from the same rounded silhouette used to clip.
    let screenshotPath = NSBezierPath(roundedRect: screenshotRect, xRadius: cornerRadius, yRadius: cornerRadius)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.065)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    NSColor.white.setFill()
    screenshotPath.fill()

    NSGraphicsContext.saveGraphicsState()
    screenshotPath.addClip()
    source.draw(in: screenshotRect, from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    // Clear the shadow before drawing the title.
    let noShadow = NSShadow()
    noShadow.shadowColor = .clear
    noShadow.set()
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byClipping
    let attributes: [NSAttributedString.Key: Any] = [
        .font: titleFont,
        .foregroundColor: ink,
        .paragraphStyle: paragraph,
    ]
    (shot.title as NSString).draw(
        in: NSRect(x: 80, y: 2488, width: 1160, height: 130),
        withAttributes: attributes
    )

    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "StoreScreenshots", code: 5)
    }
    try png.write(to: outputURL, options: .atomic)
}

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let projectURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let cssURL = projectURL.appendingPathComponent("site/assets/style.css")
let rawRootURL = projectURL.appendingPathComponent("build/store/raw", isDirectory: true)
let outputRootURL = projectURL.appendingPathComponent("build/store", isDirectory: true)

do {
    let css = try String(contentsOf: cssURL, encoding: .utf8)
    let paperHex = try value(of: "--paper", in: css)
    let inkHex = try value(of: "--ink", in: css)
    // Read all three documented palette values so a missing website token fails
    // the repeatable generation step, even though the composition only needs two.
    let mutedHex = try value(of: "--muted", in: css)
    let paper = try color(hex: paperHex)
    let ink = try color(hex: inkHex)
    _ = try color(hex: mutedHex)

    for locale in locales {
        let rawURL = rawRootURL.appendingPathComponent(locale.directory, isDirectory: true)
        let outputURL = outputRootURL.appendingPathComponent(locale.directory, isDirectory: true)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

        for shot in locale.shots {
            let localizedOutputURL = outputURL.appendingPathComponent(shot.outputName)
            try render(
                shot: shot,
                sourceURL: rawURL.appendingPathComponent(shot.inputName),
                outputURL: localizedOutputURL,
                paper: paper,
                ink: ink
            )
            // Keep the original delivery paths as Chinese compatibility copies.
            if locale.directory == "zh-Hans" {
                try Data(contentsOf: localizedOutputURL).write(
                    to: outputRootURL.appendingPathComponent(shot.outputName),
                    options: .atomic
                )
            }
            print("Wrote build/store/\(locale.directory)/\(shot.outputName) [\(paperHex), \(inkHex), \(mutedHex)]")
        }
    }
} catch {
    fputs("make-store-screenshots: \(error.localizedDescription)\n", stderr)
    exit(1)
}
