// Draws the app icon (headphones on a blue tile) into Resources/Assets.xcassets/AppIcon.appiconset.
// Run from the App folder:  swift Tools/make_icon.swift
import AppKit

let set = URL(fileURLWithPath: "Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let size = CGFloat(pixels)
    let tile = NSRect(x: size * 0.1, y: size * 0.1, width: size * 0.8, height: size * 0.8)
    NSGradient(colors: [NSColor(red: 0.16, green: 0.42, blue: 0.95, alpha: 1),
                        NSColor(red: 0.05, green: 0.2, blue: 0.6, alpha: 1)])!
        .draw(in: NSBezierPath(roundedRect: tile, xRadius: size * 0.18, yRadius: size * 0.18), angle: -90)
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    let symbol = NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    let s = symbol.size
    symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)@\(scale)x.png"
        try render(points * scale).write(to: set.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: set.appendingPathComponent("Contents.json"))
try #"{"info":{"author":"xcode","version":1}}"#.data(using: .utf8)!
    .write(to: set.deletingLastPathComponent().appendingPathComponent("Contents.json"))
