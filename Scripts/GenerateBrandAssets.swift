import AppKit
import Foundation

private let fileManager = FileManager.default
private let projectRoot = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")

private func bitmap(
    logicalSize: CGSize,
    scale: Int,
    draw: () -> Void
) throws -> Data {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(logicalSize.width) * scale,
        pixelsHigh: Int(logicalSize.height) * scale,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    representation.size = logicalSize
    guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    draw()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

private func drawCaptureMark(in rect: CGRect, lineWidth: CGFloat) {
    NSColor.white.setStroke()

    let inset = lineWidth / 2
    let length = rect.width * 0.34
    let path = NSBezierPath()
    path.lineWidth = lineWidth
    path.lineCapStyle = .square
    path.lineJoinStyle = .miter

    path.move(to: CGPoint(x: rect.minX + inset, y: rect.maxY - length))
    path.line(to: CGPoint(x: rect.minX + inset, y: rect.maxY - inset))
    path.line(to: CGPoint(x: rect.minX + length, y: rect.maxY - inset))

    path.move(to: CGPoint(x: rect.maxX - length, y: rect.maxY - inset))
    path.line(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
    path.line(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - length))

    path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY + length))
    path.line(to: CGPoint(x: rect.minX + inset, y: rect.minY + inset))
    path.line(to: CGPoint(x: rect.minX + length, y: rect.minY + inset))

    path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY + inset))
    path.line(to: CGPoint(x: rect.maxX - inset, y: rect.minY + inset))
    path.line(to: CGPoint(x: rect.maxX - inset, y: rect.minY + length))
    path.stroke()
}

private func drawAppMark(in canvas: CGRect, outerPadding: CGFloat) {
    let backgroundRect = canvas.insetBy(dx: outerPadding, dy: outerPadding)
    let backgroundPath = NSBezierPath(
        roundedRect: backgroundRect,
        xRadius: backgroundRect.width * 0.22,
        yRadius: backgroundRect.height * 0.22
    )
    let gradient = NSGradient(
        starting: NSColor(srgbRed: 0.24, green: 0.70, blue: 1, alpha: 1),
        ending: NSColor(srgbRed: 0.025, green: 0.40, blue: 0.94, alpha: 1)
    )
    gradient?.draw(in: backgroundPath, angle: -60)

    let markInset = backgroundRect.width * 0.22
    let markRect = backgroundRect.insetBy(dx: markInset, dy: markInset)
    drawCaptureMark(in: markRect, lineWidth: max(1, backgroundRect.width * 0.055))

    let font = NSFont.systemFont(
        ofSize: backgroundRect.width * 0.32,
        weight: .heavy
    )
    let text = "C"
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    let textSize = text.size(withAttributes: attributes)
    text.draw(
        at: CGPoint(
            x: backgroundRect.midX - textSize.width / 2,
            y: backgroundRect.midY - textSize.height / 2 - backgroundRect.height * 0.015
        ),
        withAttributes: attributes
    )
}

private func writeMenuBarAssets() throws {
    let directory = projectRoot
        .appendingPathComponent("CapDeck/Assets.xcassets/CapDeckMenuBarLogo.imageset")
    let logicalSize = CGSize(width: 15, height: 15)

    for scale in 1 ... 3 {
        let data = try bitmap(logicalSize: logicalSize, scale: scale) {
            NSColor.clear.setFill()
            NSBezierPath(rect: CGRect(origin: .zero, size: logicalSize)).fill()

            drawCaptureMark(
                in: CGRect(x: 2, y: 2, width: 11, height: 11),
                lineWidth: 2
            )
        }
        try data.write(
            to: directory.appendingPathComponent("CapDeckMenuBarLogo-\(scale)x.png"),
            options: .atomic
        )
    }
}

private func writeBrandAssets() throws {
    let directory = projectRoot
        .appendingPathComponent("CapDeck/Assets.xcassets/CapDeckBrandLogo.imageset")
    let logicalSize = CGSize(width: 640, height: 272)
    let text = "CapDeck"
    var fontSize: CGFloat = 76
    var font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    var attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]

    while text.size(withAttributes: attributes).width > 320 {
        fontSize -= 1
        font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
        attributes[.font] = font
    }
    let textSize = text.size(withAttributes: attributes)

    for scale in 1 ... 3 {
        let data = try bitmap(logicalSize: logicalSize, scale: scale) {
            let gradient = NSGradient(
                starting: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.115, alpha: 1),
                ending: NSColor(srgbRed: 0.045, green: 0.047, blue: 0.05, alpha: 1)
            )
            gradient?.draw(in: CGRect(origin: .zero, size: logicalSize), angle: -90)

            drawCaptureMark(
                in: CGRect(x: 82, y: 75, width: 126, height: 126),
                lineWidth: 18
            )

            NSColor.white.withAlphaComponent(0.62).setFill()
            NSBezierPath(rect: CGRect(x: 245, y: 68, width: 2, height: 136)).fill()

            text.draw(
                at: CGPoint(x: 286, y: (logicalSize.height - textSize.height) / 2 - 2),
                withAttributes: attributes
            )
        }
        try data.write(
            to: directory.appendingPathComponent("CapDeckBrandLogo-\(scale)x.png"),
            options: .atomic
        )
    }
}

private func writeAppLogoAssets() throws {
    let directory = projectRoot
        .appendingPathComponent("CapDeck/Assets.xcassets/AppLogo.imageset")
    let logicalSize = CGSize(width: 24, height: 24)

    for scale in 1 ... 3 {
        let data = try bitmap(logicalSize: logicalSize, scale: scale) {
            NSColor.clear.setFill()
            NSBezierPath(rect: CGRect(origin: .zero, size: logicalSize)).fill()
            drawAppMark(
                in: CGRect(origin: .zero, size: logicalSize),
                outerPadding: 1
            )
        }
        try data.write(
            to: directory.appendingPathComponent("AppLogo-\(scale)x.png"),
            options: .atomic
        )
    }
}

private func writeAppIconAssets() throws {
    let directory = projectRoot
        .appendingPathComponent("CapDeck/Assets.xcassets/AppIcon.appiconset")

    for dimension in [16, 32, 64, 128, 256, 512, 1024] {
        let logicalSize = CGSize(width: dimension, height: dimension)
        let data = try bitmap(logicalSize: logicalSize, scale: 1) {
            NSColor.clear.setFill()
            NSBezierPath(rect: CGRect(origin: .zero, size: logicalSize)).fill()
            drawAppMark(
                in: CGRect(origin: .zero, size: logicalSize),
                outerPadding: CGFloat(dimension) * 0.065
            )
        }
        try data.write(
            to: directory.appendingPathComponent("AppIcon-\(dimension).png"),
            options: .atomic
        )
    }
}

try writeMenuBarAssets()
try writeBrandAssets()
try writeAppLogoAssets()
try writeAppIconAssets()
