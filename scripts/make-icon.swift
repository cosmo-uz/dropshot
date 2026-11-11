// Draws the placeholder Dropshot icon at every size macOS wants.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit
import CoreGraphics

func drawIcon(size: Int) -> Data? {
    let s = CGFloat(size)
    guard let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    // macOS icon grid: 824/1024 rounded square, centred.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = body.width * 0.2237
    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Soft drop shadow under the tile.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
        color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(bodyPath)
    context.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.5, alpha: 1))
    context.fillPath()
    context.restoreGState()

    // Wallpaper-like gradient.
    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    let colors = [
        CGColor(red: 0.36, green: 0.52, blue: 1.0, alpha: 1),
        CGColor(red: 0.55, green: 0.33, blue: 0.95, alpha: 1),
        CGColor(red: 0.93, green: 0.36, blue: 0.62, alpha: 1),
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 0.55, 1]) {
        context.drawLinearGradient(
            gradient, start: CGPoint(x: body.minX, y: body.maxY),
            end: CGPoint(x: body.maxX, y: body.minY), options: [])
    }

    // The island: black, hanging from the top edge, rounded at the bottom.
    let islandWidth = body.width * 0.66
    let islandHeight = body.height * 0.52
    let island = CGRect(
        x: body.midX - islandWidth / 2, y: body.maxY - islandHeight,
        width: islandWidth, height: islandHeight + radius)
    let islandRadius = body.width * 0.11
    context.setShadow(
        offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.04,
        color: CGColor(gray: 0, alpha: 0.4))
    context.addPath(CGPath(
        roundedRect: island, cornerWidth: islandRadius, cornerHeight: islandRadius, transform: nil))
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0, color: nil)

    // The screenshot thumbnail inside it.
    let cardWidth = islandWidth * 0.72
    let cardHeight = cardWidth * 0.62
    let card = CGRect(
        x: body.midX - cardWidth / 2, y: island.minY + islandHeight * 0.14,
        width: cardWidth, height: cardHeight)
    let cardRadius = cardWidth * 0.1
    let cardPath = CGPath(roundedRect: card, cornerWidth: cardRadius, cornerHeight: cardRadius, transform: nil)
    context.saveGState()
    context.addPath(cardPath)
    context.clip()
    let cardColors = [
        CGColor(red: 1.0, green: 0.72, blue: 0.3, alpha: 1),
        CGColor(red: 1.0, green: 0.42, blue: 0.5, alpha: 1),
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: nil, colors: cardColors, locations: [0, 1]) {
        context.drawLinearGradient(
            gradient, start: CGPoint(x: card.minX, y: card.maxY),
            end: CGPoint(x: card.maxX, y: card.minY), options: [])
    }
    // A little "sun and hills" so it reads as a picture.
    context.setFillColor(CGColor(gray: 1, alpha: 0.9))
    let sun = cardHeight * 0.22
    context.fillEllipse(in: CGRect(
        x: card.minX + cardWidth * 0.16, y: card.maxY - cardHeight * 0.2 - sun, width: sun, height: sun))
    context.setFillColor(CGColor(gray: 1, alpha: 0.55))
    context.move(to: CGPoint(x: card.minX, y: card.minY))
    context.addLine(to: CGPoint(x: card.minX + cardWidth * 0.38, y: card.minY + cardHeight * 0.5))
    context.addLine(to: CGPoint(x: card.minX + cardWidth * 0.58, y: card.minY + cardHeight * 0.26))
    context.addLine(to: CGPoint(x: card.minX + cardWidth * 0.76, y: card.minY + cardHeight * 0.44))
    context.addLine(to: CGPoint(x: card.maxX, y: card.minY + cardHeight * 0.12))
    context.addLine(to: CGPoint(x: card.maxX, y: card.minY))
    context.closePath()
    context.fillPath()
    context.restoreGState()
    context.addPath(cardPath)
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.35))
    context.setLineWidth(max(1, s * 0.006))
    context.strokePath()
    context.restoreGState()

    guard let image = context.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
}

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <output.iconset>\n".utf8))
    exit(2)
}
let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    guard let data = drawIcon(size: points * scale) else {
        FileHandle.standardError.write(Data("could not draw \(name)\n".utf8))
        exit(1)
    }
    try data.write(to: out.appendingPathComponent(name))
}
