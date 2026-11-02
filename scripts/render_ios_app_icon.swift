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
    color(11, 19, 27).setFill()
    bounds.fill()
    let s = CGFloat(size)
    color(64, 199, 194).withAlphaComponent(0.48).setStroke()
    let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: s * 0.165, dy: s * 0.165))
    ring.lineWidth = s * 0.018; ring.stroke()
    for (start, end, tint) in [
        (NSPoint(x: s * 0.31, y: s * 0.70), NSPoint(x: s * 0.69, y: s * 0.30), color(218, 240, 245)),
        (NSPoint(x: s * 0.69, y: s * 0.70), NSPoint(x: s * 0.31, y: s * 0.30), color(90, 224, 194))
    ] {
        tint.setStroke()
        let stick = NSBezierPath()
        stick.move(to: start); stick.line(to: end)
        stick.lineWidth = s * 0.09; stick.lineCapStyle = .round
        stick.stroke()
    }
    color(250, 196, 89).setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.43, y: s * 0.43, width: s * 0.14, height: s * 0.14)).fill()
    color(90, 224, 194).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.33, y: s * 0.16, width: s * 0.34, height: s * 0.025), xRadius: 2, yRadius: 2).fill()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url, options: .atomic)
}

try renderPNG(size: 1_024, to: appIconURL)
try renderPNG(size: 512, to: brandMarkURL)
