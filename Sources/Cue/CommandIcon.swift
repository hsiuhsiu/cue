import CoreGraphics
import CoreText
import CueCore

/// Small, fixed artwork. Rasterize once on a worker; result rows only read cached images.
enum CommandIcon: CaseIterable, Sendable {
    case updateIndex, clipboardHistory, sleep, lockScreen, screenOff
    case convertToTraditional, convertToSimplified, chineseConversionSettings
    case googleSearch, webSearchSettings, cleanLink, emojiSearch, calculator
    case askGPT, translateGPT, gptSettings
    case windowControls, windowSettings

    init?(_ result: LauncherResult) {
        switch result {
        case .application, .file: return nil
        case .calculation, .conversion, .currencyStatus: self = .calculator
        case .cleanLink: self = .cleanLink
        case .emojiSearch: self = .emojiSearch
        case .googleSearch, .googleSearchIn, .chooseSearchBrowser: self = .googleSearch
        case .askGPT: self = .askGPT
        case .translateGPT: self = .translateGPT
        case .gptSettings: self = .gptSettings
        case .windowControls: self = .windowControls
        case .windowSettings: self = .windowSettings
        case .webSearchSettings: self = .webSearchSettings
        case .updateIndex: self = .updateIndex
        case .clipboardHistory: self = .clipboardHistory
        case .sleep: self = .sleep
        case .lockScreen: self = .lockScreen
        case .screenOff: self = .screenOff
        case .convertToTraditional: self = .convertToTraditional
        case .convertToSimplified: self = .convertToSimplified
        case .chineseConversionSettings: self = .chineseConversionSettings
        }
    }

    var resultID: String {
        switch self {
        case .calculator: LauncherResult.calculationID
        case .cleanLink: LauncherResult.cleanLink.id
        case .emojiSearch: LauncherResult.emojiSearch.id
        case .googleSearch: LauncherResult.googleSearch.id
        case .askGPT: LauncherResult.askGPT.id
        case .translateGPT: LauncherResult.translateGPT.id
        case .gptSettings: LauncherResult.gptSettings.id
        case .windowControls: LauncherResult.windowControls.id
        case .windowSettings: LauncherResult.windowSettings.id
        case .webSearchSettings: LauncherResult.webSearchSettings.id
        case .updateIndex: LauncherResult.updateIndex.id
        case .clipboardHistory: LauncherResult.clipboardHistory.id
        case .sleep: LauncherResult.sleep.id
        case .lockScreen: LauncherResult.lockScreen.id
        case .screenOff: LauncherResult.screenOff.id
        case .convertToTraditional: LauncherResult.convertToTraditional.id
        case .convertToSimplified: LauncherResult.convertToSimplified.id
        case .chineseConversionSettings: LauncherResult.chineseConversionSettings.id
        }
    }

    /// Two backing scales keep both ordinary and Retina displays sharp.
    func render(scale: Int) -> CGImage? {
        let pixels = 28 * scale
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        let tile = CGPath(roundedRect: CGRect(x: 1, y: 1, width: 26, height: 26),
                          cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(tile)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        context.addPath(tile)
        context.setStrokeColor(CGColor(red: 0.77, green: 0.85, blue: 0.90, alpha: 1))
        context.setLineWidth(0.5)
        context.strokePath()

        // Flat ink, quiet framing, and generous space around each silhouette.
        // No gradient masks, glow, or filled symbol backgrounds to compete with text.
        let ink = CGColor(red: 0.13, green: 0.43, blue: 0.66, alpha: 1)
        context.setStrokeColor(ink)
        context.setFillColor(ink)
        context.setLineWidth(1.4)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        drawGlyph(in: context)
        return context.makeImage()
    }

    private func drawGlyph(in c: CGContext) {
        func rounded(_ rect: CGRect, radius: CGFloat) {
            c.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            c.strokePath()
        }
        func line(_ points: [CGPoint]) {
            c.addLines(between: points)
            c.strokePath()
        }
        func arrow(from start: CGPoint, to end: CGPoint, head: CGFloat = 2) {
            let length = hypot(end.x - start.x, end.y - start.y)
            let dx = (end.x - start.x) / length, dy = (end.y - start.y) / length
            line([start, end])
            line([CGPoint(x: end.x - head * dx - head * 0.8 * dy,
                          y: end.y - head * dy + head * 0.8 * dx), end,
                  CGPoint(x: end.x - head * dx + head * 0.8 * dy,
                          y: end.y - head * dy - head * 0.8 * dx)])
        }
        func moon(in rect: CGRect) {
            let r = rect.width / 2
            let center = CGPoint(x: rect.midX, y: rect.midY)
            c.addArc(center: center, radius: r, startAngle: .pi / 2, endAngle: 0, clockwise: false)
            c.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                       control1: CGPoint(x: rect.minX + rect.width * 0.625, y: rect.minY + rect.height * 0.3125),
                       control2: CGPoint(x: rect.minX + rect.width * 0.3125, y: rect.minY + rect.height * 0.625))
            c.closePath()
            c.strokePath()
        }
        func character(_ text: String, size: CGFloat, center: CGPoint) {
            let font = CTFontCreateWithName("PingFangTC-Medium" as CFString, size, nil)
            let attributed = CFAttributedStringCreate(nil, text as CFString, [
                kCTFontAttributeName: font,
                kCTForegroundColorFromContextAttributeName: true
            ] as CFDictionary)!
            let textLine = CTLineCreateWithAttributedString(attributed)
            let box = CTLineGetBoundsWithOptions(textLine, .useGlyphPathBounds)
            c.textPosition = CGPoint(x: center.x - box.midX, y: center.y - box.midY)
            CTLineDraw(textLine, c)
        }

        func gear(center: CGPoint) {
            let outline = CGMutablePath()
            for i in 0..<24 {
                let angle = CGFloat(i) * .pi / 12
                let radius: CGFloat = (i % 4 == 1 || i % 4 == 2) ? 3.5 : 2.7
                let point = CGPoint(x: center.x + cos(angle) * radius,
                                    y: center.y + sin(angle) * radius)
                if i == 0 { outline.move(to: point) } else { outline.addLine(to: point) }
            }
            outline.closeSubpath()
            c.addPath(outline)
            c.strokePath()
            c.strokeEllipse(in: CGRect(x: center.x - 1.1, y: center.y - 1.1, width: 2.2, height: 2.2))
        }

        switch self {
        case .askGPT, .gptSettings:
            rounded(CGRect(x: 5.5, y: 10, width: 17, height: 12), radius: 3)
            line([CGPoint(x: 9, y: 10), CGPoint(x: 8, y: 6), CGPoint(x: 13, y: 10)])
            for x: CGFloat in [10, 14, 18] {
                c.fillEllipse(in: CGRect(x: x - 0.8, y: 15.2, width: 1.6, height: 1.6))
            }
            if self == .gptSettings {
                c.setFillColor(CGColor(gray: 1, alpha: 1))
                c.fillEllipse(in: CGRect(x: 15.5, y: 3, width: 10, height: 10))
                c.setLineWidth(1)
                gear(center: CGPoint(x: 20.5, y: 8))
            }
        case .translateGPT:
            character("A", size: 11, center: CGPoint(x: 9, y: 18))
            character("譯", size: 11, center: CGPoint(x: 19, y: 10))
            c.setLineWidth(1.1)
            arrow(from: CGPoint(x: 15, y: 21), to: CGPoint(x: 22, y: 21), head: 1.5)
            arrow(from: CGPoint(x: 13, y: 7), to: CGPoint(x: 6, y: 7), head: 1.5)
        case .calculator:
            rounded(CGRect(x: 7, y: 5, width: 14, height: 18), radius: 2)
            rounded(CGRect(x: 10, y: 16, width: 8, height: 4), radius: 0.5)
            for x: CGFloat in [10.5, 14, 17.5] {
                for y: CGFloat in [9, 12.5] {
                    c.fillEllipse(in: CGRect(x: x - 0.7, y: y - 0.7, width: 1.4, height: 1.4))
                }
            }
        case .webSearchSettings:
            c.strokeEllipse(in: CGRect(x: 5.5, y: 12, width: 10, height: 10))
            line([CGPoint(x: 14, y: 13.5), CGPoint(x: 17, y: 10.5)])
            c.setLineWidth(1.1)
            gear(center: CGPoint(x: 20.5, y: 7.5))
        case .emojiSearch:
            c.strokeEllipse(in: CGRect(x: 6, y: 6, width: 16, height: 16))
            c.fillEllipse(in: CGRect(x: 10, y: 15, width: 1.8, height: 1.8))
            c.fillEllipse(in: CGRect(x: 16.2, y: 15, width: 1.8, height: 1.8))
            c.move(to: CGPoint(x: 10, y: 12))
            c.addCurve(to: CGPoint(x: 18, y: 12), control1: CGPoint(x: 11, y: 8), control2: CGPoint(x: 17, y: 8))
            c.strokePath()
        case .cleanLink:
            // Interlocking chain links and a small cleaning sparkle.
            c.saveGState()
            c.translateBy(x: 12, y: 13)
            c.rotate(by: .pi / 4)
            rounded(CGRect(x: -8, y: -3, width: 10, height: 6), radius: 3)
            rounded(CGRect(x: -2, y: -3, width: 10, height: 6), radius: 3)
            c.restoreGState()
            c.addLines(between: [
                CGPoint(x: 21, y: 23.5), CGPoint(x: 21.8, y: 21.3),
                CGPoint(x: 24, y: 20.5), CGPoint(x: 21.8, y: 19.7),
                CGPoint(x: 21, y: 17.5), CGPoint(x: 20.2, y: 19.7),
                CGPoint(x: 18, y: 20.5), CGPoint(x: 20.2, y: 21.3),
            ])
            c.closePath()
            c.fillPath()
        case .googleSearch:
            c.strokeEllipse(in: CGRect(x: 6.5, y: 10.5, width: 11, height: 11))
            line([CGPoint(x: 16, y: 12), CGPoint(x: 22, y: 6)])
        case .sleep:
            moon(in: CGRect(x: 6.5, y: 6.5, width: 15, height: 15))
        case .lockScreen:
            c.move(to: CGPoint(x: 10, y: 15))
            c.addLine(to: CGPoint(x: 10, y: 18.5))
            c.addArc(center: CGPoint(x: 14, y: 18.5), radius: 4,
                     startAngle: .pi, endAngle: 0, clockwise: true)
            c.addLine(to: CGPoint(x: 18, y: 15)); c.strokePath()
            rounded(CGRect(x: 7, y: 5.5, width: 14, height: 10), radius: 2.4)
            line([CGPoint(x: 14, y: 11.5), CGPoint(x: 14, y: 8.8)])
        case .windowControls, .windowSettings:
            rounded(CGRect(x: 5, y: 7, width: 18, height: 14), radius: 2)
            line([CGPoint(x: 5, y: 17), CGPoint(x: 23, y: 17)])
            if self == .windowControls {
                line([CGPoint(x: 13, y: 7), CGPoint(x: 13, y: 17)])
                arrow(from: CGPoint(x: 16, y: 10), to: CGPoint(x: 20, y: 14), head: 1.3)
            } else {
                c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fillEllipse(in: CGRect(x: 14, y: 3, width: 12, height: 12))
                c.setStrokeColor(CGColor(red: 0.13, green: 0.43, blue: 0.66, alpha: 1))
                for angle in stride(from: 0.0, to: Double.pi * 2, by: Double.pi / 4) {
                    line([CGPoint(x: 20 + cos(angle) * 3, y: 9 + sin(angle) * 3), CGPoint(x: 20 + cos(angle) * 4.5, y: 9 + sin(angle) * 4.5)])
                }
                c.strokeEllipse(in: CGRect(x: 17, y: 6, width: 6, height: 6))
                c.strokeEllipse(in: CGRect(x: 19, y: 8, width: 2, height: 2))
            }
        case .screenOff:
            rounded(CGRect(x: 5, y: 9, width: 18, height: 12.5), radius: 2)
            line([CGPoint(x: 14, y: 9), CGPoint(x: 14, y: 6)])
            line([CGPoint(x: 10.5, y: 6), CGPoint(x: 17.5, y: 6)])
            c.setLineWidth(1.15)
            moon(in: CGRect(x: 11, y: 12.3, width: 6.4, height: 6.4))
        case .clipboardHistory:
            // Break the top edge around the clip, keeping every contour outlined.
            c.move(to: CGPoint(x: 10.5, y: 21))
            c.addLine(to: CGPoint(x: 8.5, y: 21))
            c.addQuadCurve(to: CGPoint(x: 7, y: 19.5), control: CGPoint(x: 7, y: 21))
            c.addLine(to: CGPoint(x: 7, y: 7))
            c.addQuadCurve(to: CGPoint(x: 8.5, y: 5.5), control: CGPoint(x: 7, y: 5.5))
            c.addLine(to: CGPoint(x: 19.5, y: 5.5))
            c.addQuadCurve(to: CGPoint(x: 21, y: 7), control: CGPoint(x: 21, y: 5.5))
            c.addLine(to: CGPoint(x: 21, y: 19.5))
            c.addQuadCurve(to: CGPoint(x: 19.5, y: 21), control: CGPoint(x: 21, y: 21))
            c.addLine(to: CGPoint(x: 17.5, y: 21)); c.strokePath()
            rounded(CGRect(x: 10.5, y: 19.5, width: 7, height: 3), radius: 1)
            for y: CGFloat in [16, 12.5, 9] {
                line([CGPoint(x: 10.5, y: y), CGPoint(x: y == 9 ? 15.5 : 17.5, y: y)])
            }
        case .convertToTraditional, .convertToSimplified:
            arrow(from: CGPoint(x: 4.8, y: 14), to: CGPoint(x: 9.3, y: 14), head: 1.7)
            character(self == .convertToTraditional ? "繁" : "简", size: 13,
                      center: CGPoint(x: 18.4, y: 14))
        case .updateIndex:
            // A centered app grid and one surrounding arc share a visual center.
            c.setLineWidth(1)
            for x: CGFloat in [10, 15] {
                for y: CGFloat in [10, 15] {
                    rounded(CGRect(x: x, y: y, width: 3, height: 3), radius: 0.65)
                }
            }
            c.setLineWidth(1.3)
            let center = CGPoint(x: 14, y: 14)
            let radius: CGFloat = 8.4
            let endAngle: CGFloat = .pi * 0.55
            c.addArc(center: center, radius: radius, startAngle: .pi * 0.12,
                     endAngle: endAngle, clockwise: true)
            c.strokePath()
            let end = CGPoint(x: center.x + cos(endAngle) * radius, y: center.y + sin(endAngle) * radius)
            let tangent = CGPoint(x: sin(endAngle), y: -cos(endAngle))
            arrow(from: CGPoint(x: end.x - tangent.x * 0.1, y: end.y - tangent.y * 0.1),
                  to: end, head: 2)
        case .chineseConversionSettings:
            // Keep both return directions at the sides, separate from the
            // larger Settings gear and the diagonal conversion targets.
            character("繁", size: 10.5, center: CGPoint(x: 10.2, y: 19.3))
            character("简", size: 10.5, center: CGPoint(x: 16.2, y: 8.7))
            c.setLineWidth(1)
            gear(center: CGPoint(x: 21.1, y: 21.1))
            c.setLineWidth(1.1)
            arrow(from: CGPoint(x: 4.6, y: 6.8), to: CGPoint(x: 4.6, y: 12.8), head: 1.3)
            arrow(from: CGPoint(x: 23.8, y: 14.5), to: CGPoint(x: 23.8, y: 8.5), head: 1.3)
        }
    }
}
