import AppKit
import CueCore

/// Disk access and icon decoding never run in the input or drawing path.
@MainActor
final class AppIconCache {
    private var images: [String: NSImage] = [:]
    private var pending: [String: Task<Void, Never>] = [:]
    private var generation = 0
    private var commandImages: [CommandIcon: NSImage] = [:]
    private var commandTask: Task<Void, Never>?
    private let placeholder = NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
    var onLoad: ((String) -> Void)?

    init() {
        commandTask = Task { [weak self] in
            let rendered = await Task.detached(priority: .userInitiated) {
                CommandIcon.allCases.map { command in
                    (command, [1, 2].compactMap { command.render(scale: $0) })
                }
            }.value
            guard let self, !Task.isCancelled else { return }
            for (command, bitmaps) in rendered {
                let image = NSImage(size: NSSize(width: 28, height: 28))
                for bitmap in bitmaps {
                    let representation = NSBitmapImageRep(cgImage: bitmap)
                    representation.size = image.size
                    image.addRepresentation(representation)
                }
                guard !bitmaps.isEmpty else { continue }
                self.commandImages[command] = image
                self.onLoad?(command.resultID)
            }
            self.commandTask = nil
        }
    }

    deinit { commandTask?.cancel() }

    func image(for command: CommandIcon) -> NSImage {
        commandImages[command] ?? placeholder
    }

    func image(for application: IndexedApplication) -> NSImage {
        if let image = images[application.id] { return image }
        request(application)
        return placeholder
    }

    func prepare(_ applications: [IndexedApplication]) {
        for application in applications { request(application) }
    }

    func invalidate() {
        generation += 1
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
        images.removeAll(keepingCapacity: true)
    }

    private func request(_ application: IndexedApplication) {
        guard images[application.id] == nil, pending[application.id] == nil else { return }
        let generation = generation
        let path = application.url.path
        pending[application.id] = Task { [weak self] in
            let bitmap = await Task.detached(priority: .userInitiated) {
                // Apple documents icon(forFile:) as safe to call from any thread.
                let icon = NSWorkspace.shared.icon(forFile: path)
                var rect = CGRect(x: 0, y: 0, width: 64, height: 64)
                guard let source = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil),
                      let context = CGContext(
                        data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                      ) else { return nil as CGImage? }
                context.draw(source, in: rect)
                return context.makeImage()
            }.value
            guard let self, !Task.isCancelled, generation == self.generation else { return }
            if let bitmap {
                self.images[application.id] = NSImage(cgImage: bitmap, size: NSSize(width: 32, height: 32))
            } else {
                self.images[application.id] = self.placeholder
            }
            self.pending[application.id] = nil
            self.onLoad?(application.id)
        }
    }
}
