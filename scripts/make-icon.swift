#!/usr/bin/env swift

import AppKit
import Foundation

// Generate the 1024x1024 master PNG for the GarbageMan app icon.
// Brand: Emerald Labs.
// Output: $REPO/.icon-build/icon_1024.png

_ = NSApplication.shared  // bootstraps AppKit subsystems used by SF symbol lookup.

let repo = ProcessInfo.processInfo.environment["GM_REPO_DIR"]
    ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().path
let outDir = URL(fileURLWithPath: repo).appending(path: ".icon-build")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let side: CGFloat = 1024

// Render straight into an NSBitmapImageRep. `image.lockFocus()` doesn't work
// reliably without a running event loop, but a bitmap-backed graphics context
// works fine.
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(side),
    pixelsHigh: Int(side),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 32
) else {
    FileHandle.standardError.write(Data("Failed to allocate bitmap\n".utf8))
    exit(1)
}
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = gctx
let ctx = gctx.cgContext

let rect = CGRect(x: 0, y: 0, width: side, height: side)
let cornerRadius: CGFloat = side * 0.22

let rounded = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
ctx.saveGState()
rounded.addClip()

let darkEmerald = NSColor(red: 11/255.0, green: 47/255.0, blue: 33/255.0, alpha: 1)
let brightEmerald = NSColor(red: 31/255.0, green: 120/255.0, blue: 84/255.0, alpha: 1)
let topGloss = NSColor(red: 56/255.0, green: 156/255.0, blue: 116/255.0, alpha: 1)

if let radial = NSGradient(colors: [topGloss, brightEmerald, darkEmerald],
                           atLocations: [0.0, 0.5, 1.0],
                           colorSpace: .deviceRGB) {
    radial.draw(in: rect, relativeCenterPosition: NSPoint(x: -0.15, y: 0.35))
}

if let sheen = NSGradient(colors: [
    NSColor(white: 1, alpha: 0.18),
    NSColor(white: 1, alpha: 0.0),
    NSColor(white: 0, alpha: 0.18)
], atLocations: [0.0, 0.45, 1.0], colorSpace: .deviceRGB) {
    sheen.draw(in: rect, angle: 270)
}

NSColor(white: 1, alpha: 0.14).setStroke()
let rim = NSBezierPath(roundedRect: rect.insetBy(dx: 6, dy: 6), xRadius: cornerRadius - 6, yRadius: cornerRadius - 6)
rim.lineWidth = 4
rim.stroke()

let cream = NSColor(red: 245/255.0, green: 240/255.0, blue: 232/255.0, alpha: 1.0)
if let baseSymbol = NSImage(systemSymbolName: "trash.fill", accessibilityDescription: nil) {
    let sizeConfig = NSImage.SymbolConfiguration(pointSize: side * 0.52, weight: .semibold)
    let tintConfig = NSImage.SymbolConfiguration(paletteColors: [cream])
    let configured = baseSymbol.withSymbolConfiguration(sizeConfig.applying(tintConfig)) ?? baseSymbol

    let imgSize = configured.size
    let glyphRect = CGRect(
        x: (side - imgSize.width) / 2,
        y: (side - imgSize.height) / 2 - 30,
        width: imgSize.width,
        height: imgSize.height
    )

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.shadowBlurRadius = 36
    shadow.shadowOffset = NSSize(width: 0, height: -16)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    configured.draw(in: glyphRect)
    NSGraphicsContext.restoreGraphicsState()
} else {
    FileHandle.standardError.write(Data("warning: trash.fill symbol unavailable; icon will lack glyph\n".utf8))
}

ctx.restoreGState()
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Failed to encode PNG\n".utf8))
    exit(1)
}
let outURL = outDir.appending(path: "icon_1024.png")
try png.write(to: outURL)
print("Wrote \(outURL.path) (\(png.count) bytes)")
