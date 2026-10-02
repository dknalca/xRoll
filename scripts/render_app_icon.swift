import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let sizes = [16, 32, 128, 256, 512]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}

func drawIcon(size: Int) throws -> Data {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    color(11, 19, 27).setFill()
    NSBezierPath(roundedRect: rect, xRadius: CGFloat(size) * 0.215, yRadius: CGFloat(size) * 0.215).fill()
    let s = CGFloat(size)
    color(64, 199, 194).withAlphaComponent(0.48).setStroke()
    let ring = NSBezierPath(ovalIn: rect.insetBy(dx: s * 0.165, dy: s * 0.165))
    ring.lineWidth = max(1, s * 0.018); ring.stroke()
    for (start, end, tint) in [
        (NSPoint(x: s * 0.31, y: s * 0.70), NSPoint(x: s * 0.69, y: s * 0.30), color(218, 240, 245)),
        (NSPoint(x: s * 0.69, y: s * 0.70), NSPoint(x: s * 0.31, y: s * 0.30), color(90, 224, 194))
    ] {
        tint.setStroke()
        let stick = NSBezierPath()
        stick.move(to: start); stick.line(to: end)
        stick.lineWidth = max(1.5, s * 0.09); stick.lineCapStyle = .round
        stick.stroke()
    }
    color(250, 196, 89).setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.43, y: s * 0.43, width: s * 0.14, height: s * 0.14)).fill()
    color(90, 224, 194).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.33, y: s * 0.16, width: s * 0.34, height: max(1, s * 0.025)), xRadius: 2, yRadius: 2).fill()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return bitmap.representation(using: .png, properties: [:])!
}

for size in sizes {
    try drawIcon(size: size).write(to: output.appendingPathComponent("icon_\(size)x\(size).png"))
    try drawIcon(size: size * 2).write(to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
