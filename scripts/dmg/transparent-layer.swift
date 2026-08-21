// Turns the opaque black-on-white QR artwork into an Icon Composer layer:
// black modules stay opaque, white becomes transparent (anti-aliased edges keep partial alpha).
import AppKit
let src = URL(fileURLWithPath: CommandLine.arguments[1]), dst = URL(fileURLWithPath: CommandLine.arguments[2])
let rep = NSBitmapImageRep(data: try! Data(contentsOf: src))!
let w = rep.pixelsWide, h = rep.pixelsHigh
let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
for y in 0..<h { for x in 0..<w {
    let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
    let lum = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    out.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: max(0, min(1, 1 - lum))), atX: x, y: y)
} }
try! out.representation(using: .png, properties: [:])!.write(to: dst)
print("layer written: \(w)x\(h)")
