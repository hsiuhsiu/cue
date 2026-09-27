import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Offline packaging only: retain the supplied artwork and prepare native icon resolutions.
// Run from the repository root with `xcrun swift scripts/prepare-branding.swift`.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let files = FileManager.default
let output = root.appendingPathComponent("Resources")
let branding = root.appendingPathComponent("docs/branding")
let iconset = root.appendingPathComponent(".build/branding/AppIcon.iconset")
try files.createDirectory(at: iconset, withIntermediateDirectories: true)

func read(_ url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("Cannot read \(url.path)")
    }
    return image
}

func context(_ size: Int) -> CGContext {
    CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
              bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func write(_ image: CGImage, _ url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination), "Cannot write \(url.path)")
}

func scaled(_ image: CGImage, size: Int, inset: CGFloat = 0, tint: CGFloat? = nil,
            updateBadge: Bool = false) -> CGImage {
    let canvas = context(size)
    canvas.interpolationQuality = .high
    let available = CGFloat(size) - inset * 2
    let scale = available / CGFloat(max(image.width, image.height))
    let width = CGFloat(image.width) * scale, height = CGFloat(image.height) * scale
    canvas.draw(image, in: CGRect(x: (CGFloat(size) - width) / 2,
                                 y: (CGFloat(size) - height) / 2, width: width, height: height))
    if let tint {
        // A template uses alpha only; use a uniform color for standalone documentation previews.
        canvas.setBlendMode(.sourceIn)
        canvas.setFillColor(CGColor(gray: tint, alpha: 1))
        canvas.fill(CGRect(x: 0, y: 0, width: size, height: size))
        canvas.setBlendMode(.normal)
    }
    if updateBadge {
        let unit = CGFloat(size) / 18
        canvas.setBlendMode(.clear)
        canvas.fillEllipse(in: CGRect(x: 11.5 * unit, y: 0, width: 6.5 * unit, height: 6.5 * unit))
        canvas.setBlendMode(.normal)
        canvas.setFillColor(CGColor(gray: 0, alpha: 1))
        canvas.fillEllipse(in: CGRect(x: 13 * unit, y: 1.5 * unit, width: 3.5 * unit, height: 3.5 * unit))
    }
    return canvas.makeImage()!
}

let app = read(branding.appendingPathComponent("source/app-icon.png"))
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 1 ? "" : "@2x"
        write(scaled(app, size: points * scale),
              iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
    }
}
write(scaled(app, size: 256), branding.appendingPathComponent("cue-icon.png"))

let mark = read(branding.appendingPathComponent("source/menu-bar-mark.png"))
// Bounds of the supplied visible mark (alpha > 8), excluding faint stray pixels in its padding.
// Keep a two-pixel source margin to preserve the original antialiased edges.
let cropped = mark.cropping(to: CGRect(x: 320, y: 352, width: 612, height: 608))!
for scale in [1, 2] {
    let suffix = scale == 1 ? "" : "@2x"
    for badge in [false, true] {
        let name = badge ? "MenuBarIconUpdateTemplate" : "MenuBarIconTemplate"
        write(scaled(cropped, size: 18 * scale, inset: CGFloat(scale), tint: 0, updateBadge: badge),
              output.appendingPathComponent("\(name)\(suffix).png"))
    }
}
for (name, tint) in [("light", CGFloat(0)), ("dark", CGFloat(1))] {
    write(scaled(cropped, size: 72, inset: 4, tint: tint),
          branding.appendingPathComponent("menu-bar-\(name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed; run with access to macOS image services.\n".utf8))
    exit(1)
}
print("Prepared AppIcon.icns, 18/36-pixel menu bar templates, and GitHub previews.")
