#!/usr/bin/env swift
import AppKit

// Generates AppIcon.icns: a blue→purple squircle with a white sparkles glyph,
// matching the app's accent. Run from the repo root: `swift scripts/make-icon.swift`.

func makeIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    // Squircle background with a small margin (macOS icons sit inside the canvas).
    let margin = size * 0.085
    let rect = NSRect(x: margin, y: margin, width: size - margin * 2, height: size - margin * 2)
    let corner = rect.width * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.31, green: 0.55, blue: 1.00, alpha: 1),  // blue
        NSColor(calibratedRed: 0.56, green: 0.36, blue: 1.00, alpha: 1),  // purple
    ])!
    gradient.draw(in: path, angle: -55)

    // White sparkles glyph, centered.
    let cfg = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        NSColor.white.set()
        let sr = NSRect(origin: .zero, size: symbol.size)
        symbol.draw(in: sr)
        sr.fill(using: .sourceAtop)
        tinted.unlockFocus()

        let s = symbol.size
        let origin = NSPoint(x: (size - s.width) / 2, y: (size - s.height) / 2)
        tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
    }

    image.unlockFocus()
    return image
}

func png(_ image: NSImage, _ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = URL(filePath: "scripts/AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

// (point size, @-suffix) → filename, for every required iconset entry.
let entries: [(base: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
    (256, 1), (256, 2), (512, 1), (512, 2),
]
for e in entries {
    let pixels = e.base * e.scale
    let img = makeIcon(size: CGFloat(pixels))
    let name = e.scale == 1 ? "icon_\(e.base)x\(e.base).png" : "icon_\(e.base)x\(e.base)@2x.png"
    try! png(img, pixels).write(to: iconset.appending(path: name))
}
print("Wrote \(entries.count) PNGs to \(iconset.path)")
