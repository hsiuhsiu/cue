import AppKit
import CoreText
import CueCore

/// Color emoji font loading, shaping, and bitmap drawing stay off the input thread.
/// Only the current nine targets can queue work; older completed glyphs are bounded.
@MainActor
final class EmojiGlyphCache {
    static let maximumGlyphs = 128
    private var images: [String: NSImage] = [:]
    private var resolved = Set<String>()
    private var order: [String] = []
    private var targets: [String] = []
    private var task: Task<Void, Never>?
    var onLoad: (() -> Void)?
    var isLoading: Bool { targets.contains { !resolved.contains($0) } }
    var cachedGlyphCount: Int { resolved.count }

    deinit { task?.cancel() }

    func image(for entry: EmojiEntry) -> NSImage? { images[entry.id] }

    func prepare(_ entries: [EmojiEntry]) {
        targets = Array(entries.prefix(9)).map(\.emoji)
        startBatchIfNeeded()
    }

    private func startBatchIfNeeded() {
        guard task == nil else { return }
        let missing = targets.filter { !resolved.contains($0) }
        guard !missing.isEmpty else { return }
        task = Task { [weak self] in
            let rendered = await Task.detached(priority: .userInitiated) {
                let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 28, nil)
                return missing.map { emoji in
                    (emoji, [1, 2].compactMap { Self.render(emoji, font: font, scale: $0) })
                }
            }.value
            guard !Task.isCancelled, let self else { return }
            var updatesVisibleGlyph = false
            for (emoji, bitmaps) in rendered {
                self.resolved.insert(emoji)
                self.order.append(emoji)
                updatesVisibleGlyph = updatesVisibleGlyph || self.targets.contains(emoji)
                if !bitmaps.isEmpty {
                    let image = NSImage(size: NSSize(width: 28, height: 28))
                    for bitmap in bitmaps {
                        let representation = NSBitmapImageRep(cgImage: bitmap)
                        representation.size = image.size
                        image.addRepresentation(representation)
                    }
                    self.images[emoji] = image
                }
            }
            // Protect visible targets while evicting the oldest unused results.
            while self.order.count > Self.maximumGlyphs {
                guard let index = self.order.firstIndex(where: { !self.targets.contains($0) }) else { break }
                let emoji = self.order.remove(at: index)
                self.images[emoji] = nil
                self.resolved.remove(emoji)
            }
            self.task = nil
            if updatesVisibleGlyph { self.onLoad?() }
            self.startBatchIfNeeded()
        }
    }

    nonisolated private static func render(_ emoji: String, font: CTFont, scale: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: 28 * scale, height: 28 * scale,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let string = NSAttributedString(string: emoji, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font
        ])
        let line = CTLineCreateWithAttributedString(string)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        // The color-font em box is slightly larger than its visible bitmap.
        // Fit that box to the row's 28-point glyph area without cropping modifiers.
        let fit = min(1, 28 / max(width, ascent + descent))
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        context.translateBy(x: (28 - width * fit) / 2, y: (28 - (ascent + descent) * fit) / 2 + descent * fit)
        context.scaleBy(x: fit, y: fit)
        context.textPosition = .zero
        CTLineDraw(line, context)
        return context.makeImage()
    }
}
