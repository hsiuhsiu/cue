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
    private struct BrowserTarget: Equatable, Sendable {
        let id: String
        let bundleIdentifier: String?
    }
    private var browserTargets: [BrowserTarget] = []
    private var browserImages: [String: NSImage] = [:]
    private var browserPaths: [String: String] = [:]
    private var browserTask: Task<Void, Never>?
    private var browserGeneration = 0
    private var browserRefreshRequested = false
    private let resolveBrowser: @Sendable (String?) -> URL?
    private let loadBrowserIcon: @Sendable (URL) -> CGImage?
    private let placeholder = NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
    var onLoad: ((String) -> Void)?

    init(resolveBrowser: @escaping @Sendable (String?) -> URL? = AppIconCache.systemBrowserURL,
         loadBrowserIcon: @escaping @Sendable (URL) -> CGImage? = AppIconCache.systemBrowserIcon) {
        self.resolveBrowser = resolveBrowser
        self.loadBrowserIcon = loadBrowserIcon
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

    deinit {
        commandTask?.cancel()
        browserTask?.cancel()
    }

    func image(for command: CommandIcon) -> NSImage {
        commandImages[command] ?? placeholder
    }

    /// A pure memory lookup. Browser discovery and compositing never begin while typing.
    func image(forWebSearch result: LauncherResult) -> NSImage {
        browserImages[result.id] ?? image(for: .googleSearch)
    }

    func prepareBrowserIcons(_ browsers: [WebSearchBrowser]) {
        let targets = [BrowserTarget(id: LauncherResult.googleSearch.id, bundleIdentifier: nil)]
            + browsers.prefix(WebSearchBrowser.maximumAddedBrowsers).map {
                BrowserTarget(id: LauncherResult.googleSearchIn($0).id, bundleIdentifier: $0.bundleIdentifier)
            }
        guard targets != browserTargets else { return }
        browserTargets = targets
        browserGeneration += 1
        let ids = Set(targets.map(\.id))
        browserImages = browserImages.filter { ids.contains($0.key) }
        browserPaths = browserPaths.filter { ids.contains($0.key) }
        refreshBrowserIcons()
    }

    /// Called at invocation and configuration boundaries, never for query changes.
    /// Re-resolve locally so a changed system default is reflected on the next invocation;
    /// unchanged applications keep their already decoded and composed image objects.
    func refreshBrowserIcons() {
        guard !browserTargets.isEmpty else { return }
        guard browserTask == nil else {
            // Keep at most one worker alive even if configuration changes while
            // Launch Services is still answering. Only the newest list will run next.
            browserRefreshRequested = true
            return
        }
        browserRefreshRequested = false
        let targets = browserTargets
        let paths = browserPaths
        let generation = browserGeneration
        browserTask = Task { [weak self, resolveBrowser, loadBrowserIcon] in
            let updates = await Task.detached(priority: .utility) {
                targets.compactMap { target -> (String, String, [CGImage])? in
                    let url = resolveBrowser(target.bundleIdentifier)
                    let path = url?.path ?? ""
                    guard paths[target.id] != path else { return nil }
                    let bitmap = url.flatMap(loadBrowserIcon)
                    let rendered = bitmap.map { bitmap in
                        [1, 2].compactMap { Self.renderWebSearchBadge(bitmap, scale: $0) }
                    } ?? []
                    return (target.id, path, rendered)
                }
            }.value
            guard let self, !Task.isCancelled else { return }
            for (id, path, bitmaps) in updates {
                guard generation == self.browserGeneration else { break }
                self.browserPaths[id] = path
                if bitmaps.isEmpty {
                    self.browserImages[id] = nil
                } else {
                    let image = NSImage(size: NSSize(width: 28, height: 28))
                    for bitmap in bitmaps {
                        let representation = NSBitmapImageRep(cgImage: bitmap)
                        representation.size = image.size
                        image.addRepresentation(representation)
                    }
                    self.browserImages[id] = image
                }
                self.onLoad?(id)
            }
            self.browserTask = nil
            if self.browserRefreshRequested || generation != self.browserGeneration {
                self.refreshBrowserIcons()
            }
        }
    }

    nonisolated static func renderWebSearchBadge(_ bitmap: CGImage, scale: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: 28 * scale, height: 28 * scale,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        context.interpolationQuality = .high
        let border = CGColor(red: 0.77, green: 0.85, blue: 0.90, alpha: 1)
        let tile = CGPath(roundedRect: CGRect(x: 1, y: 1, width: 26, height: 26),
                          cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(tile)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        context.addPath(tile)
        context.setStrokeColor(border)
        context.setLineWidth(0.5)
        context.strokePath()
        // Give the lens and its entire handle their own silhouette. A handle
        // pointing left cannot disappear behind the browser badge at the right.
        context.setStrokeColor(CGColor(red: 0.13, green: 0.43, blue: 0.66, alpha: 1))
        context.setLineWidth(1.4)
        context.setLineCap(.round)
        context.strokeEllipse(in: CGRect(x: 4.5, y: 14, width: 10, height: 10))
        context.move(to: CGPoint(x: 6, y: 15.5))
        context.addLine(to: CGPoint(x: 3.2, y: 12.7))
        context.strokePath()
        let backing = CGPath(roundedRect: CGRect(x: 14, y: 0.5, width: 13.5, height: 13.5),
                             cornerWidth: 3.5, cornerHeight: 3.5, transform: nil)
        context.addPath(backing)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fillPath()
        context.addPath(backing)
        context.setLineWidth(0.5)
        context.setStrokeColor(border)
        context.strokePath()
        context.draw(bitmap, in: CGRect(x: 15, y: 1.5, width: 11.5, height: 11.5))
        return context.makeImage()
    }

    nonisolated private static func systemBrowserURL(_ identifier: String?) -> URL? {
        let url: URL?
        if let identifier {
            url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        } else {
            // Launch Services lookup only; this does not open or request the URL.
            url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://www.google.com/")!)
        }
        guard let url, url.isFileURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    nonisolated private static func systemBrowserIcon(_ url: URL) -> CGImage? {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        var rect = CGRect(x: 0, y: 0, width: 32, height: 32)
        guard let source = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        return context.makeImage()
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
        // A manual reindex also picks up replaced app artwork at an unchanged path.
        browserGeneration += 1
        browserPaths.removeAll(keepingCapacity: true)
        refreshBrowserIcons()
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
