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
    color(16, 20, 28).setFill()
    NSBezierPath(roundedRect: rect, xRadius: CGFloat(size) * 0.215, yRadius: CGFloat(size) * 0.215).fill()
    let panel = rect.insetBy(dx: CGFloat(size) * 0.185, dy: CGFloat(size) * 0.185)
    color(29, 44, 66).setFill(); NSBezierPath(roundedRect: panel, xRadius: CGFloat(size) * 0.09, yRadius: CGFloat(size) * 0.09).fill()
    let padSize = CGFloat(size) * 0.17; let gap = CGFloat(size) * 0.02
    for row in 0..<2 { for column in 0..<2 {
        let x = CGFloat(size) * 0.265 + CGFloat(column) * (padSize + gap)
        let y = CGFloat(size) * 0.43 + CGFloat(row) * (padSize + gap)
        color(0, 114, 178).setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: padSize, height: padSize), xRadius: CGFloat(size) * 0.028, yRadius: CGFloat(size) * 0.028).fill()
    }}
    NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: CGFloat(size) * 0.30, y: CGFloat(size) * 0.62, width: CGFloat(size) * 0.09, height: CGFloat(size) * 0.09)).fill()
    NSBezierPath(roundedRect: NSRect(x: CGFloat(size) * 0.51, y: CGFloat(size) * 0.63, width: CGFloat(size) * 0.055, height: CGFloat(size) * 0.055), xRadius: 2, yRadius: 2).fill()
    color(230, 159, 0).setStroke(); let line = NSBezierPath(); line.move(to: NSPoint(x: CGFloat(size) * 0.29, y: CGFloat(size) * 0.28)); line.line(to: NSPoint(x: CGFloat(size) * 0.71, y: CGFloat(size) * 0.28)); line.lineWidth = CGFloat(size) * 0.035; line.lineCapStyle = .round; line.stroke()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return bitmap.representation(using: .png, properties: [:])!
}

for size in sizes {
    try drawIcon(size: size).write(to: output.appendingPathComponent("icon_\(size)x\(size).png"))
    try drawIcon(size: size * 2).write(to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
