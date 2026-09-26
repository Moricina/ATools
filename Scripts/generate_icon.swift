import Foundation
import AppKit

func generateIcon() {
    let size: CGFloat = 1024
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return
    }

    // High quality interpolation
    ctx.interpolationQuality = .high

    // 1. Squircle dimensions (Apple HIG standard: inset 100pt, 824x824, radius 185)
    let inset: CGFloat = 100
    let squircleRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let cornerRadius: CGFloat = 185
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // 2. Drop Shadow for Squircle
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 38, color: NSColor(white: 0.0, alpha: 0.42).cgColor)
    ctx.setFillColor(NSColor.black.cgColor)
    ctx.addPath(squirclePath)
    ctx.fillPath()
    ctx.restoreGState()

    // 3. Background Gradient
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.clip()

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradientColors = [
        NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.22, alpha: 1.0).cgColor, // Deep Midnight Navy
        NSColor(calibratedRed: 0.16, green: 0.22, blue: 0.50, alpha: 1.0).cgColor, // Royal Indigo
        NSColor(calibratedRed: 0.10, green: 0.42, blue: 0.88, alpha: 1.0).cgColor  // Vibrant Electric Blue
    ] as CFArray
    let locations: [CGFloat] = [0.0, 0.55, 1.0]
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: locations) {
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: squircleRect.minX, y: squircleRect.maxY),
            end: CGPoint(x: squircleRect.maxX, y: squircleRect.minY),
            options: []
        )
    }

    // 4. Subtle Ambient Light / Glow from Top
    if let radialGradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            NSColor(white: 1.0, alpha: 0.18).cgColor,
            NSColor(white: 1.0, alpha: 0.0).cgColor
        ] as CFArray,
        locations: [0.0, 1.0]
    ) {
        ctx.drawRadialGradient(
            radialGradient,
            startCenter: CGPoint(x: squircleRect.midX, y: squircleRect.maxY - 50),
            startRadius: 0,
            endCenter: CGPoint(x: squircleRect.midX, y: squircleRect.maxY - 50),
            endRadius: 450,
            options: []
        )
    }

    // 5. Stylized Launcher Emblem (Sparkle & Search Beam & Grid Symbol)
    let centerX = squircleRect.midX
    let centerY = squircleRect.midY

    // 5.1 Subtle Background Grid Dots / Tiles (Represents Maye Nano App Launcher Shelf)
    let tileCols = 3
    let tileRows = 2
    let tileSize: CGFloat = 68
    let tileSpacing: CGFloat = 28
    let startX = centerX - CGFloat(tileCols) * tileSize / 2.0 - CGFloat(tileCols - 1) * tileSpacing / 2.0
    let startY = centerY - 140

    for r in 0..<tileRows {
        for c in 0..<tileCols {
            let tx = startX + CGFloat(c) * (tileSize + tileSpacing)
            let ty = startY + CGFloat(r) * (tileSize + tileSpacing)
            let tRect = CGRect(x: tx, y: ty, width: tileSize, height: tileSize)
            let tPath = CGPath(roundedRect: tRect, cornerWidth: 16, cornerHeight: 16, transform: nil)
            ctx.setFillColor(NSColor(white: 1.0, alpha: 0.12).cgColor)
            ctx.addPath(tPath)
            ctx.fillPath()
        }
    }

    // 5.2 Large Iconic Stylized "Rocket / Search Beam" Emblem
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: NSColor(calibratedRed: 0.2, green: 0.6, blue: 1.0, alpha: 0.6).cgColor)

    // Draw Sleek Magnifying Glass & Rocket Sparkle
    let lensRadius: CGFloat = 135
    let lensCenter = CGPoint(x: centerX - 30, y: centerY + 65)

    // Outer Glass Ring
    ctx.setLineWidth(32)
    ctx.setStrokeColor(NSColor.white.cgColor)
    ctx.strokeEllipse(in: CGRect(x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius, width: lensRadius * 2, height: lensRadius * 2))

    // Handle (Angled at 45 degrees extending down-right)
    let handlePath = CGMutablePath()
    let handleStart = CGPoint(x: lensCenter.x + lensRadius * 0.707, y: lensCenter.y - lensRadius * 0.707)
    let handleEnd = CGPoint(x: lensCenter.x + 230, y: lensCenter.y - 230)
    handlePath.move(to: handleStart)
    handlePath.addLine(to: handleEnd)
    ctx.setLineCap(.round)
    ctx.setLineWidth(34)
    ctx.addPath(handlePath)
    ctx.strokePath()

    // 5.3 Glowing Sparkle Star at Center of Lens (4-point sparkle)
    let starCenter = lensCenter
    let starPath = CGMutablePath()
    let starR1: CGFloat = 62
    let starR2: CGFloat = 18
    for i in 0..<8 {
        let angle = CGFloat(i) * .pi / 4.0 - .pi / 2.0
        let r = (i % 2 == 0) ? starR1 : starR2
        let pt = CGPoint(x: starCenter.x + r * cos(angle), y: starCenter.y + r * sin(angle))
        if i == 0 { starPath.move(to: pt) } else { starPath.addLine(to: pt) }
    }
    starPath.closeSubpath()
    ctx.setFillColor(NSColor(calibratedRed: 0.45, green: 0.88, blue: 1.0, alpha: 0.95).cgColor)
    ctx.addPath(starPath)
    ctx.fillPath()

    ctx.restoreGState()

    // 6. Fine High-Gloss Rim Light (Edge Stroke)
    ctx.setLineWidth(2.5)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.28).cgColor)
    ctx.addPath(squirclePath)
    ctx.strokePath()

    ctx.restoreGState()

    image.unlockFocus()

    // Export to iconset
    guard let tiffData = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiffData) else {
        print("Failed to get bitmap image rep")
        return
    }

    let fileManager = FileManager.default
    let baseDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
    let resourcesDir = baseDir.appendingPathComponent("Resources")
    let iconsetDir = resourcesDir.appendingPathComponent("AppIcon.iconset")

    try? fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

    let sizes: [(String, Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024)
    ]

    for (name, px) in sizes {
        let dest = iconsetDir.appendingPathComponent(name)
        let scaledImage = NSImage(size: NSSize(width: px, height: px))
        scaledImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: px, height: px), from: .zero, operation: .copy, fraction: 1.0)
        scaledImage.unlockFocus()

        if let scaledTiff = scaledImage.tiffRepresentation,
           let scaledRep = NSBitmapImageRep(data: scaledTiff),
           let pngData = scaledRep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: dest)
        }
    }

    // Save master 1024 png
    if let masterData = rep.representation(using: .png, properties: [:]) {
        try? masterData.write(to: resourcesDir.appendingPathComponent("AppIcon_1024.png"))
    }

    print("Successfully generated iconset at: \(iconsetDir.path)")
}

generateIcon()
