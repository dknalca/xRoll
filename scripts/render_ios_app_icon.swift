import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fatalError("Uso: render_ios_app_icon.swift <AppIcon.png> <BrandMark.png>")
}

let appIconURL = URL(fileURLWithPath: CommandLine.arguments[1])
let brandMarkURL = URL(fileURLWithPath: CommandLine.arguments[2])

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}

func renderPNG(size: Int, to url: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let bounds = NSRect(x: 0, y: 0, width: size, height: size)
    color(16, 20, 28).setFill()
    bounds.fill()

    let panel = bounds.insetBy(dx: CGFloat(size) * 0.185, dy: CGFloat(size) * 0.185)
    color(29, 44, 66).setFill()
    NSBezierPath(roundedRect: panel, xRadius: CGFloat(size) * 0.09, yRadius: CGFloat(size) * 0.09).fill()
    let padSize = CGFloat(size) * 0.17
    let gap = CGFloat(size) * 0.02
    for row in 0..<2 {
        for column in 0..<2 {
            let x = CGFloat(size) * 0.265 + CGFloat(column) * (padSize + gap)
            let y = CGFloat(size) * 0.43 + CGFloat(row) * (padSize + gap)
            color(0, 114, 178).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: padSize, height: padSize), xRadius: CGFloat(size) * 0.028, yRadius: CGFloat(size) * 0.028).fill()
        }
    }
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: CGFloat(size) * 0.30, y: CGFloat(size) * 0.62, width: CGFloat(size) * 0.09, height: CGFloat(size) * 0.09)).fill()
    NSBezierPath(roundedRect: NSRect(x: CGFloat(size) * 0.51, y: CGFloat(size) * 0.63, width: CGFloat(size) * 0.055, height: CGFloat(size) * 0.055), xRadius: CGFloat(size) * 0.01, yRadius: CGFloat(size) * 0.01).fill()
    color(230, 159, 0).setStroke()
    let hitLine = NSBezierPath()
    hitLine.move(to: NSPoint(x: CGFloat(size) * 0.29, y: CGFloat(size) * 0.28))
    hitLine.line(to: NSPoint(x: CGFloat(size) * 0.71, y: CGFloat(size) * 0.28))
    hitLine.lineWidth = CGFloat(size) * 0.035
    hitLine.lineCapStyle = .round
    hitLine.stroke()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url, options: .atomic)
}

try renderPNG(size: 1_024, to: appIconURL)
try renderPNG(size: 512, to: brandMarkURL)
