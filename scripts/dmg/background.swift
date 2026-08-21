// Renders the dmg window background (540×380 pt) at 1x and 2x.
// Same visual system as scan.libra.wiki: paper, ink, one hairline, a dashed arrow.
import AppKit

let W: CGFloat = 540, H: CGFloat = 380
func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
let paper = rgb(0xF7F7F5), ink = rgb(0x111111), muted = rgb(0x6B6B6B), line = rgb(0xE3E3DF)

/// Draw text with a top-left origin (AppKit's origin is bottom-left).
func text(_ s: String, x: CGFloat, top: CGFloat, size: CGFloat, weight: NSFont.Weight, color: NSColor,
          kern: CGFloat = 0, alignRight: Bool = false) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .kern: kern]
    let str = NSAttributedString(string: s, attributes: attrs)
    let sz = str.size()
    let originX = alignRight ? x - sz.width : x
    str.draw(at: NSPoint(x: originX, y: H - top - sz.height))
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    paper.setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()

    // Title block
    text("LibraScan", x: 40, top: 34, size: 26, weight: .semibold, color: ink, kern: -0.6)
    text("把它拖进「应用程序」文件夹  ·  Drag it into the Applications folder", x: 40, top: 72, size: 13, weight: .regular, color: muted)
    line.setStroke()
    let rule = NSBezierPath(); rule.lineWidth = 1
    rule.move(to: NSPoint(x: 40, y: H - 100.5)); rule.line(to: NSPoint(x: W - 40, y: H - 100.5)); rule.stroke()

    // Dashed arrow between the two icon slots (icon centres at x=140 and x=400, y=190; icons are 128 pt)
    ink.setStroke()
    let arrow = NSBezierPath(); arrow.lineWidth = 2; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    arrow.setLineDash([1, 9], count: 2, phase: 0)
    arrow.move(to: NSPoint(x: 222, y: H - 190)); arrow.line(to: NSPoint(x: 308, y: H - 190)); arrow.stroke()
    let head = NSBezierPath(); head.lineWidth = 2; head.lineCapStyle = .round; head.lineJoinStyle = .round
    head.move(to: NSPoint(x: 310, y: H - 182)); head.line(to: NSPoint(x: 320, y: H - 190)); head.line(to: NSPoint(x: 310, y: H - 198)); head.stroke()

    // Footer notes
    text("首次启动请按引导开启「辅助功能」权限，仅用于发送按键。", x: 40, top: 318, size: 11.5, weight: .regular, color: muted)
    text("On first launch, allow Accessibility — it's only used to post keystrokes.", x: 40, top: 336, size: 11.5, weight: .regular, color: muted)
    text("scan.libra.wiki", x: W - 40, top: 318, size: 11.5, weight: .medium, color: muted, alignRight: true)

    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
for (scale, name) in [(CGFloat(1), "background.png"), (CGFloat(2), "background@2x.png")] {
    let rep = render(scale: scale)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: out).appendingPathComponent(name))
}
print("background rendered")
