import AppKit
import CoreText
import CueCore
import Darwin

/// Real renderer, cache, and launcher view; no windows, system actions, user
/// preferences, installed-app inventory, or clipboard access are needed.
@main
struct CheckCommandIcons {
    static let commands: [(CommandIcon, LauncherResult, String)] = [
        (.updateIndex, .updateIndex, "Update index"),
        (.clipboardHistory, .clipboardHistory, "Clipboard"),
        (.sleep, .sleep, "Sleep"),
        (.lockScreen, .lockScreen, "Lock"),
        (.screenOff, .screenOff, "Screen off"),
        (.convertToTraditional, .convertToTraditional, "Traditional"),
        (.convertToSimplified, .convertToSimplified, "Simplified"),
        (.chineseConversionSettings, .chineseConversionSettings, "Conversion settings"),
    ]

    @MainActor
    static func main() async {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.mainMenu = nil
        let checks = IconChecks()
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard arguments.isEmpty || (arguments.count == 2 && arguments[0] == "--preview") else {
                throw CheckError.usage
            }
            await checkRenderer(checks)
            let cache = await checkCache(checks)
            await checkView(checks)
            if arguments.count == 2 {
                let destination = URL(fileURLWithPath: arguments[1])
                try exportPreview(cache: cache, to: destination)
                print("Artwork preview: \(destination.path)")
            }
        } catch {
            checks.expect(false, "Unexpected harness error: \(error)")
        }
        checks.expect(!application.isActive && application.windows.allSatisfy { !$0.isVisible },
                      "The checks must remain inactive with no visible windows")
        if !checks.failures.isEmpty {
            checks.failures.forEach { print("FAIL: \($0)") }
            print("Command-icon regression failed: \(checks.failures.count) failures / \(checks.count) checks.")
            exit(1)
        }
        print("Command-icon regression passed: \(checks.count) checks; two scales, distinct artwork, stable cache, callbacks, invalidation, and native row updates. Lookup timing excludes rendering and input delivery.")
    }

    @MainActor
    private static func checkRenderer(_ checks: IconChecks) async {
        checks.expect(CommandIcon.allCases.count == 8 && Set(commands.map { $0.0 }).count == 8,
                      "All eight built-in command icons must be covered")
        for (icon, result, _) in commands {
            checks.expect(CommandIcon(result) == icon && icon.resultID == result.id,
                          "Artwork must map to the stable result ID for \(result.name)")
        }
        let app = IndexedApplication(name: "Synthetic", url: URL(fileURLWithPath: "/SyntheticCueIcon.app"))
        checks.expect(CommandIcon(.application(app)) == nil, "Apps must keep using their own icons")
        let rendered = await Task.detached(priority: .userInitiated) {
            let offMain = pthread_main_np() == 0
            return (offMain, CommandIcon.allCases.map { command in
                (command, [1, 2].map { command.render(scale: $0) })
            })
        }.value
        checks.expect(rendered.0, "The renderer fixture must exercise the background execution path")
        var fingerprints: [Int: Set<Data>] = [1: [], 2: []]
        for (command, bitmaps) in rendered.1 {
            for (offset, optionalBitmap) in bitmaps.enumerated() {
                let scale = offset + 1
                guard let bitmap = optionalBitmap,
                      let bytes = bitmap.dataProvider?.data as Data? else {
                    checks.expect(false, "\(command) must render at \(scale)x")
                    continue
                }
                checks.expect(bitmap.width == 28 * scale && bitmap.height == 28 * scale,
                              "\(command) must have the intended \(scale)x pixel dimensions")
                checks.expect(bytes.contains { $0 != 0 }, "\(command) must not render an empty bitmap")
                fingerprints[scale, default: []].insert(bytes)
            }
        }
        for scale in [1, 2] {
            checks.expect(fingerprints[scale]?.count == 8, "All eight glyphs must have distinct \(scale)x artwork")
        }
    }

    @MainActor
    private static func checkCache(_ checks: IconChecks) async -> AppIconCache {
        let cache = AppIconCache()
        var callbacks: [String] = []
        var callbacksOnMain = true
        cache.onLoad = { id in
            callbacksOnMain = callbacksOnMain && Thread.isMainThread
            callbacks.append(id)
        }
        let placeholders = commands.map { cache.image(for: $0.0) }
        checks.expect(callbacks.isEmpty, "Construction and cold lookups must return before rendering callbacks")
        checks.expect(placeholders.allSatisfy { $0 === placeholders[0] },
                      "Cold command lookups must reuse one placeholder without per-row image creation")
        cache.invalidate()
        await checks.eventually("Invalidation during initial rendering must still deliver all command images") {
            callbacks.count == commands.count
        }
        checks.expect(callbacksOnMain, "Every cache callback must execute on the main actor's thread")
        checks.expect(Set(callbacks) == Set(commands.map { $0.1.id }) && callbacks.count == 8,
                      "Each built-in command must publish its matching stable ID exactly once")
        let images = commands.map { cache.image(for: $0.0) }
        for (offset, image) in images.enumerated() {
            checks.expect(image !== placeholders[offset], "Ready artwork must replace the placeholder")
            checks.expect(image.size == NSSize(width: 28, height: 28) && !image.isTemplate,
                          "Ready artwork must retain its 28-point size and colors")
            let representations = image.representations.compactMap { $0 as? NSBitmapImageRep }
            checks.expect(representations.count == 2 && Set(representations.map(\.pixelsWide)) == [28, 56]
                          && representations.allSatisfy { $0.pixelsWide == $0.pixelsHigh && $0.size == image.size },
                          "Cached artwork must retain matching ordinary and Retina representations")
            checks.expect(cache.image(for: commands[offset].0) === image, "Repeated lookup must return the same cached image")
        }
        cache.invalidate()
        checks.expect(commands.enumerated().allSatisfy { cache.image(for: $0.element.0) === images[$0.offset] },
                      "Reindexing app icons must not discard already rendered command artwork")

        // Report rather than assert performance: cache lookup only, not NSImage
        // drawing, and no device-dependent fixed timing thresholds.
        var samples: [Double] = []
        var identityHits = 0
        for _ in 0..<100 {
            let start = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<100 {
                for (offset, command) in commands.enumerated() {
                    if cache.image(for: command.0) === images[offset] { identityHits += 1 }
                }
            }
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 800)
        }
        samples.sort()
        checks.expect(identityHits == 80_000 && callbacks.count == 8,
                      "Warm lookups must keep image identity without scheduling additional ready callbacks")
        print(String(format: "Cached command lookup (100 batches of 800): p50 %.1f ns/op; p95 %.1f; max batch average %.1f; identity hits %d.",
                     samples[49], samples[94], samples[99], identityHits))

        weak var released: AppIconCache?
        do {
            let temporary = AppIconCache()
            released = temporary
        }
        checks.expect(released == nil, "An initial background task must not retain an abandoned cache")
        return cache
    }

    @MainActor
    private static func checkView(_ checks: IconChecks) async {
        let model = LauncherModel()
        let view = LauncherView(model: model, onSubmit: {}, onCancel: {}, onSettings: {})
        let window = NSPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        guard let scroll = view.subviews.compactMap({ $0 as? NSScrollView }).first,
              let table = scroll.documentView as? NSTableView else {
            checks.expect(false, "The real launcher must expose its native result table")
            return
        }
        let dataSource = CountingDataSource(view)
        table.dataSource = dataSource
        // Neither query yields. All icon callbacks therefore arrive after rows
        // for the old conversion query have been replaced with screen results.
        model.setQuery("chinese")
        model.setQuery("screen")
        model.select(LauncherResult.screenOff.id)
        window.setContentSize(NSSize(width: 640, height: view.preferredHeight))
        view.layoutSubtreeIfNeeded()
        window.makeFirstResponder(view.searchField)
        let cells = model.results.indices.compactMap {
            table.view(atColumn: 0, row: $0, makeIfNecessary: true) as? NSTableCellView
        }
        checks.expect(cells.count == 2 && model.selectedResult == .screenOff,
                      "The delayed callback fixture must display Lock and Screen Off with the latter selected")
        let query = model.query
        let order = model.results.map(\.id)
        let selection = model.selectedID
        let firstResponder = window.firstResponder
        let tableSelection = table.selectedRow
        let rowUpdates = model.onChange
        var modelUpdates = 0
        model.onChange = { modelUpdates += 1; rowUpdates?() }
        let updateIcon = model.icons.onLoad
        var callbacks: [String] = []
        model.icons.onLoad = { id in callbacks.append(id); updateIcon?(id) }
        dataSource.rowCountRequests = 0
        await checks.eventually("The real view cache must finish background command rendering") { callbacks.count == 8 }
        checks.expect(model.query == query && model.results.map(\.id) == order && model.selectedID == selection,
                      "Delayed icon callbacks must preserve current query, order, and numbered selection")
        checks.expect(modelUpdates == 0 && dataSource.rowCountRequests == 0,
                      "Icon-only callbacks must not republish the model or reload table data")
        checks.expect(window.firstResponder === firstResponder && table.selectedRow == tableSelection,
                      "Icon-only updates must preserve the field editor and selected table row")
        for (row, cell) in cells.enumerated() {
            checks.expect(table.view(atColumn: 0, row: row, makeIfNecessary: false) === cell,
                          "Delayed icons must update the existing visible cell in place")
            if let command = CommandIcon(model.results[row]) {
                checks.expect(cell.imageView?.image === model.icons.image(for: command),
                              "The visible row must receive its own ready command image")
            }
        }
        model.reset()
        let idleHeight = view.preferredHeight
        dataSource.rowCountRequests = 0
        model.icons.onLoad?(LauncherResult.screenOff.id)
        checks.expect(model.results.isEmpty && model.selectedID == nil && view.preferredHeight == idleHeight
                      && dataSource.rowCountRequests == 0,
                      "A stale callback on an empty launcher must not create rows or change its geometry")
    }

    @MainActor
    private static func exportPreview(cache: AppIconCache, to url: URL) throws {
        let width = 148 * commands.count
        guard let context = CGContext(data: nil, width: width, height: 392, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CheckError.preview }
        for (section, dark) in [true, false].enumerated() {
            let origin = CGFloat(section * 196)
            context.setFillColor(dark ? CGColor(red: 0.045, green: 0.065, blue: 0.105, alpha: 1)
                                     : CGColor(gray: 0.95, alpha: 1))
            context.fill(CGRect(x: 0, y: origin, width: CGFloat(width), height: 196))
            for (index, fixture) in commands.enumerated() {
                let x = CGFloat(index * 148 + 18)
                let image = cache.image(for: fixture.0)
                let bitmaps = image.representations.compactMap { $0 as? NSBitmapImageRep }
                guard let ordinary = bitmaps.first(where: { $0.pixelsWide == 28 })?.cgImage,
                      let enlarged = fixture.0.render(scale: 4) else { throw CheckError.preview }
                context.draw(ordinary, in: CGRect(x: x, y: origin + 130, width: 28, height: 28))
                context.interpolationQuality = .high
                context.draw(enlarged, in: CGRect(x: x, y: origin + 10, width: 112, height: 112))
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: fixture.2, attributes: [
                    .font: NSFont.systemFont(ofSize: 11),
                    .foregroundColor: dark ? NSColor.white : NSColor.black
                ]))
                context.textPosition = CGPoint(x: x, y: origin + 174)
                CTLineDraw(line, context)
            }
        }
        guard let bitmap = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: bitmap).representation(using: .png, properties: [:]) else { throw CheckError.preview }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url, options: .atomic)
    }

    private enum CheckError: Error { case usage, preview }
}

@MainActor
private final class CountingDataSource: NSObject, NSTableViewDataSource {
    let view: LauncherView
    var rowCountRequests = 0
    init(_ view: LauncherView) { self.view = view }
    func numberOfRows(in tableView: NSTableView) -> Int {
        rowCountRequests += 1
        return view.numberOfRows(in: tableView)
    }
}

@MainActor
private final class IconChecks {
    var count = 0
    var failures: [String] = []
    func expect(_ condition: Bool, _ message: String) {
        count += 1
        if !condition { failures.append(message) }
    }
    func eventually(_ message: String, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(5)) }
        expect(condition(), message)
    }
}
