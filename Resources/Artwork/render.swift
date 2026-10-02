//
//  render.swift
//  Artwork
//
//  Renders Lynx Bar's SVG artwork into the asset catalog.
//  Run from the repository root:  swift Resources/Artwork/render.swift
//

import AppKit

func render(_ svgPath: String, pixels: Int, to pngPath: String) {
    guard let image = NSImage(contentsOf: URL(fileURLWithPath: svgPath)) else {
        fatalError("Can't load \(svgPath)")
    }
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else {
        fatalError("Can't create bitmap")
    }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Can't encode \(pngPath)")
    }
    do {
        try data.write(to: URL(fileURLWithPath: pngPath))
    } catch {
        fatalError("Can't write \(pngPath): \(error)")
    }
    print("wrote \(pngPath)")
}

let assets = "Ice/Resources/Assets.xcassets"
let appIconSizes = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in appIconSizes {
    render("Resources/Artwork/AppIcon.svg", pixels: pixels, to: "\(assets)/AppIcon.appiconset/\(name).png")
}
// Control item images are 20 pt, provided at 2x (40 px), like the other image sets.
for name in ["LynxFill", "LynxStroke"] {
    render("Resources/Artwork/\(name).svg", pixels: 40, to: "\(assets)/ControlItemImages/Lynx/\(name).imageset/\(name).png")
}
