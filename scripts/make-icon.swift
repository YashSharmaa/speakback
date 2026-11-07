// Draws the speakback logo, a speech bubble holding sound-wave bars on a
// gradient tile, and writes docs/icon.png (512 x 512).
// Run from the repository root: swift scripts/make-icon.swift
import AppKit

let size: CGFloat = 512
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Tile: macOS-style rounded square with a teal-to-violet diagonal gradient.
let inset: CGFloat = 40
let tile = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 96, cornerHeight: 96, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: NSColor.black.withAlphaComponent(0.3).cgColor)
ctx.addPath(tilePath)
ctx.setFillColor(NSColor.black.cgColor)
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
let colors = [
    NSColor(srgbRed: 0.05, green: 0.72, blue: 0.70, alpha: 1).cgColor,
    NSColor(srgbRed: 0.33, green: 0.36, blue: 0.93, alpha: 1).cgColor,
    NSColor(srgbRed: 0.62, green: 0.25, blue: 0.86, alpha: 1).cgColor,
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
ctx.restoreGState()

// Speech bubble: a rounded rectangle with a tail at the lower left.
let bubble = CGRect(x: 104, y: 166, width: 304, height: 216)
let bubblePath = CGMutablePath()
bubblePath.addRoundedRect(in: bubble, cornerWidth: 72, cornerHeight: 72)
bubblePath.move(to: CGPoint(x: 150, y: 190))
bubblePath.addLine(to: CGPoint(x: 128, y: 110))
bubblePath.addLine(to: CGPoint(x: 226, y: 172))
bubblePath.closeSubpath()
ctx.addPath(bubblePath)
ctx.setFillColor(NSColor.white.cgColor)
ctx.fillPath()

// Sound-wave bars inside the bubble, tallest in the middle, in the gradient's indigo.
let heights: [CGFloat] = [44, 92, 136, 92, 44]
let barWidth: CGFloat = 26
let gap: CGFloat = 20
let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
var x = bubble.midX - total / 2
ctx.setFillColor(NSColor(srgbRed: 0.27, green: 0.33, blue: 0.90, alpha: 1).cgColor)
for h in heights {
    let bar = CGRect(x: x, y: bubble.midY - h / 2, width: barWidth, height: h)
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
    ctx.fillPath()
    x += barWidth + gap
}
NSGraphicsContext.restoreGraphicsState()

try FileManager.default.createDirectory(atPath: "docs", withIntermediateDirectories: true)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/icon.png"))
print("Wrote docs/icon.png")
