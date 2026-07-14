// Renders the Snip app icon (timeline with amber trim selection) to an
// .iconset directory. Run from Resources/: swift make_icon.swift
// Then: iconutil -c icns Snip.iconset -o AppIcon.icns
import AppKit

let sizes: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x"),
]

func draw(in ctx: CGContext, px: CGFloat) {
    let s = px / 1024.0
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
    }

    // Background rounded square with vertical gradient.
    let bgPath = CGPath(roundedRect: r(64, 64, 896, 896), cornerWidth: 200 * s, cornerHeight: 200 * s, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()
    let colors = [
        NSColor(calibratedRed: 0.17, green: 0.17, blue: 0.20, alpha: 1).cgColor,
        NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.08, alpha: 1).cgColor,
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: px), end: .zero, options: [])

    // Timeline strip.
    ctx.setFillColor(NSColor(calibratedWhite: 0.03, alpha: 1).cgColor)
    ctx.addPath(CGPath(roundedRect: r(120, 352, 784, 320), cornerWidth: 36 * s, cornerHeight: 36 * s, transform: nil))
    ctx.fillPath()

    // Frame cells: middle two selected (amber), outer two dim.
    let amber = NSColor(calibratedRed: 1.0, green: 0.69, blue: 0.23, alpha: 1)
    let cellW: CGFloat = 172, gap: CGFloat = 20
    var x: CGFloat = 152
    for index in 0..<4 {
        let selected = index == 1 || index == 2
        let color = selected ? amber.withAlphaComponent(0.92) : NSColor(calibratedRed: 0.27, green: 0.29, blue: 0.35, alpha: 1)
        ctx.setFillColor(color.cgColor)
        ctx.addPath(CGPath(roundedRect: r(x, 396, cellW, 232), cornerWidth: 20 * s, cornerHeight: 20 * s, transform: nil))
        ctx.fillPath()
        x += cellW + gap
    }

    // Trim bracket: handles + rails around selected cells.
    let selLeft: CGFloat = 152 + cellW + gap
    let selRight: CGFloat = selLeft + 2 * cellW + gap
    ctx.setFillColor(amber.cgColor)
    ctx.addPath(CGPath(roundedRect: r(selLeft - 40, 320, 40, 384), cornerWidth: 14 * s, cornerHeight: 14 * s, transform: nil))
    ctx.addPath(CGPath(roundedRect: r(selRight, 320, 40, 384), cornerWidth: 14 * s, cornerHeight: 14 * s, transform: nil))
    ctx.fillPath()
    ctx.fill(r(selLeft, 682, selRight - selLeft, 22))
    ctx.fill(r(selLeft, 320, selRight - selLeft, 22))

    // Handle grips.
    ctx.setFillColor(NSColor(calibratedWhite: 0.1, alpha: 0.85).cgColor)
    ctx.addPath(CGPath(roundedRect: r(selLeft - 28, 472, 16, 80), cornerWidth: 8 * s, cornerHeight: 8 * s, transform: nil))
    ctx.addPath(CGPath(roundedRect: r(selRight + 12, 472, 16, 80), cornerWidth: 8 * s, cornerHeight: 8 * s, transform: nil))
    ctx.fillPath()
}

func render(px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext
    ctx.clear(CGRect(x: 0, y: 0, width: px, height: px))
    ctx.saveGState()
    draw(in: ctx, px: CGFloat(px))
    ctx.restoreGState()
    gctx.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let outDir = "Snip.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
for (px, name) in sizes {
    try! render(px: px).write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("iconset written to \(outDir)")
