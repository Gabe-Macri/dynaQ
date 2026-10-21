import AppKit
import CoreGraphics

func createIconImage(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // Outer padding for macOS standard squircle look
    let inset = size * 0.08
    let iconRect = rect.insetBy(dx: inset, dy: inset)
    let cornerRadius = iconRect.width * 0.22

    // 1. Dark Technical Slate Chassis
    let path = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(CGColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1.0))
    ctx.fillPath()

    // 2. 1px Crisp Border
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(red: 0.22, green: 0.25, blue: 0.32, alpha: 1.0))
    ctx.setLineWidth(max(size * 0.015, 1.0))
    ctx.strokePath()

    // 3. Subtle Grid Lines (Hardware Rack Tone)
    let gridCount = 5
    ctx.setStrokeColor(CGColor(red: 0.15, green: 0.18, blue: 0.22, alpha: 0.6))
    ctx.setLineWidth(max(size * 0.008, 0.5))

    for i in 1..<gridCount {
        let x = iconRect.minX + (iconRect.width / CGFloat(gridCount)) * CGFloat(i)
        ctx.move(to: CGPoint(x: x, y: iconRect.minY + iconRect.height * 0.2))
        ctx.addLine(to: CGPoint(x: x, y: iconRect.maxY - iconRect.height * 0.2))
        ctx.strokePath()

        let y = iconRect.minY + (iconRect.height / CGFloat(gridCount)) * CGFloat(i)
        ctx.move(to: CGPoint(x: iconRect.minX + iconRect.width * 0.2, y: y))
        ctx.addLine(to: CGPoint(x: iconRect.maxX - iconRect.width * 0.2, y: y))
        ctx.strokePath()
    }

    // 4. Center EQ Curve Contour (CRT Phosphor Green)
    let curvePath = CGMutablePath()
    let leftX = iconRect.minX + iconRect.width * 0.18
    let rightX = iconRect.maxX - iconRect.width * 0.18
    let midY = iconRect.midY
    let peakY = iconRect.midY + iconRect.height * 0.22
    let dipY = iconRect.midY - iconRect.height * 0.12

    curvePath.move(to: CGPoint(x: leftX, y: midY))
    curvePath.addCurve(
        to: CGPoint(x: iconRect.minX + iconRect.width * 0.42, y: peakY),
        control1: CGPoint(x: leftX + iconRect.width * 0.10, y: midY),
        control2: CGPoint(x: iconRect.minX + iconRect.width * 0.30, y: peakY)
    )
    curvePath.addCurve(
        to: CGPoint(x: iconRect.minX + iconRect.width * 0.68, y: dipY),
        control1: CGPoint(x: iconRect.minX + iconRect.width * 0.52, y: peakY),
        control2: CGPoint(x: iconRect.minX + iconRect.width * 0.58, y: dipY)
    )
    curvePath.addCurve(
        to: CGPoint(x: rightX, y: midY),
        control1: CGPoint(x: iconRect.minX + iconRect.width * 0.78, y: dipY),
        control2: CGPoint(x: rightX - iconRect.width * 0.08, y: midY)
    )

    ctx.addPath(curvePath)
    ctx.setStrokeColor(CGColor(red: 0.22, green: 0.95, blue: 0.45, alpha: 1.0)) // Phosphor Green
    ctx.setLineWidth(max(size * 0.035, 2.0))
    ctx.setLineCap(.square)
    ctx.setLineJoin(.miter)
    ctx.strokePath()

    // 5. Reticle Crosshair Square at Peak
    let reticleSize = max(size * 0.08, 4.0)
    let reticleRect = CGRect(
        x: iconRect.minX + iconRect.width * 0.42 - reticleSize * 0.5,
        y: peakY - reticleSize * 0.5,
        width: reticleSize,
        height: reticleSize
    )
    ctx.addRect(reticleRect)
    ctx.setFillColor(CGColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1.0))
    ctx.fillPath()
    ctx.addRect(reticleRect)
    ctx.setStrokeColor(CGColor(red: 1.0, green: 0.70, blue: 0.18, alpha: 1.0)) // Phosphor Amber
    ctx.setLineWidth(max(size * 0.015, 1.0))
    ctx.strokePath()

    // 6. Monospace Label "[ Q ]"
    if size >= 64 {
        let text = "[ Q ]" as NSString
        let fontSize = max(size * 0.11, 8.0)
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .black)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(red: 0.92, green: 0.94, blue: 0.96, alpha: 1.0)
        ]
        let textSize = text.size(withAttributes: attrs)
        let textPoint = CGPoint(
            x: iconRect.midX - textSize.width * 0.5,
            y: iconRect.minY + iconRect.height * 0.18
        )
        text.draw(at: textPoint, withAttributes: attrs)
    }

    img.unlockFocus()
    return img
}

func savePNG(image: NSImage, path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed to encode PNG for \(path)")
        return
    }
    try? png.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
let iconsetDir = "dist/dynaQ.iconset"
try? fm.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(name: String, px: CGFloat)] = [
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

for s in sizes {
    let img = createIconImage(size: s.px)
    savePNG(image: img, path: "\(iconsetDir)/\(s.name)")
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir, "-o", "dist/AppIcon.icns"]
try? process.run()
process.waitUntilExit()

print("AppIcon.icns generated successfully at dist/AppIcon.icns")

