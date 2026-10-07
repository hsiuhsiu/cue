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
        (.commandHistory, .commandHistory, "Command history"),
        (.sleep, .sleep, "Sleep"),
        (.lockScreen, .lockScreen, "Lock"),
        (.screenOff, .screenOff, "Screen off"),
        (.convertToTraditional, .convertToTraditional, "Traditional"),
        (.convertToSimplified, .convertToSimplified, "Simplified"),
        (.chineseConversionSettings, .chineseConversionSettings, "Conversion settings"),
        (.googleSearch, .googleSearch, "Google search"),
        (.webSearchSettings, .webSearchSettings, "Search settings"),
        (.cleanLink, .cleanLink, "Clean link"),
        (.emojiSearch, .emojiSearch, "Emoji search"),
        (.askGPT, .askGPT, "Ask GPT"),
        (.translateGPT, .translateGPT, "GPT translation"),
        (.gptSettings, .gptSettings, "GPT settings"),
        (.windowControls, .windowControls, "Window controls"),
        (.windowSettings, .windowSettings, "Window settings"),
        (.calculator, .calculation(Calculator.evaluate("1+1")!), "Calculator"),
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
            await checkApplicationCache(checks)
            await checkApplicationViewInvalidation(checks)
            await checkView(checks)
            let browserImages = await checkBrowserCache(checks)
            await checkBrowserView(checks)
            if arguments.count == 2 {
                let destination = URL(fileURLWithPath: arguments[1])
                try exportPreview(cache: cache, to: destination)
                print("Artwork preview: \(destination.path)")
                let browserDestination = destination.deletingPathExtension().appendingPathExtension("browsers.png")
                try exportBrowserPreview(images: browserImages, to: browserDestination)
                print("Synthetic browser-badge preview: \(browserDestination.path)")
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
        print("Command-icon regression passed: \(checks.count) checks; two scales, distinct artwork, bounded application decoding/cache, browser badges, off-main refresh, stale callbacks, and native row isolation. Lookup timing excludes rendering and input delivery.")
    }

    @MainActor
    private static func checkRenderer(_ checks: IconChecks) async {
        checks.expect(Set(CommandIcon.allCases) == Set(commands.map { $0.0 })
                      && commands.count == CommandIcon.allCases.count,
                      "Every built-in command/action icon must be covered exactly once")
        for (icon, result, _) in commands {
            checks.expect(CommandIcon(result) == icon && icon.resultID == result.id,
                          "Artwork must map to the stable result ID for \(result.name)")
        }
        let app = IndexedApplication(name: "Synthetic", url: URL(fileURLWithPath: "/SyntheticCueIcon.app"))
        checks.expect(CommandIcon(.application(app)) == nil, "Apps must keep using their own icons")
        let browser = WebSearchBrowser(bundleIdentifier: "invalid.cue.browser", name: "Browser Fixture")
        checks.expect(CommandIcon(.googleSearchIn(browser)) == .googleSearch,
                      "Added browsers must reuse the Google search artwork")
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
            checks.expect(fingerprints[scale]?.count == commands.count, "Every glyph must have distinct \(scale)x artwork")
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
        let initialRevision = cache.revision
        cache.invalidate()
        checks.expect(cache.revision == initialRevision + 1,
                      "Invalidation advances the revision even before any application icons have loaded")
        await checks.eventually("Invalidation during initial rendering must still deliver all command images") {
            callbacks.count == commands.count
        }
        checks.expect(callbacksOnMain, "Every cache callback must execute on the main actor's thread")
        checks.expect(Set(callbacks) == Set(commands.map { $0.1.id }) && callbacks.count == commands.count,
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
        let loadedRevision = cache.revision
        checks.expect(loadedRevision == initialRevision + 1,
                      "Ordinary loading and image lookups do not advance the invalidation revision")
        cache.invalidate()
        checks.expect(cache.revision == loadedRevision + 1,
                      "Every later invalidation advances the revision exactly once")
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
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / Double(100 * commands.count))
        }
        samples.sort()
        checks.expect(identityHits == 10_000 * commands.count && callbacks.count == commands.count,
                      "Warm lookups must keep image identity without scheduling additional ready callbacks")
        print(String(format: "Cached command lookup (100 batches): p50 %.1f ns/op; p95 %.1f; max batch average %.1f; identity hits %d.",
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
    private static func checkApplicationCache(_ checks: IconChecks) async {
        let apps = (0..<300).map { index in
            IndexedApplication(name: "Synthetic \(index)", url: URL(fileURLWithPath: "/Synthetic/App\(index).app"))
        }
        let fixture = ApplicationIconFixture(blockFirst: 2)
        let cache = AppIconCache(resolveBrowser: { _ in nil }, loadBrowserIcon: { _ in nil },
                                 loadApplicationIcon: { fixture.load($0) })
        var callbacks: [String] = []
        cache.onLoad = { id in if id.hasPrefix("/Synthetic/") { callbacks.append(id) } }
        cache.prepare(Array(apps.prefix(9)))
        let placeholder = cache.image(for: apps[0])
        await checks.eventually("Only the bounded application workers enter stalled synthetic decoders") {
            fixture.state.calls.count == 2
        }
        // Both reads stay blocked across fast typing and repeated manual reindex.
        // Cancelling only their awaiting tasks would otherwise start new OS reads.
        for start in 9...50 {
            cache.prepare(Array(apps[start..<(start + 9)]))
            cache.invalidate()
        }
        let finalTargets = Array(apps[70..<79])
        cache.prepare(finalTargets)
        checks.expect(fixture.state.calls.count == 2 && fixture.state.maximumActive == 2,
                      "New queries and invalidation cannot spawn additional decoders while two OS reads remain in flight")
        fixture.releaseBlockedReads()
        await checks.eventually("After stale reads drain, the latest nine targets all become ready") {
            callbacks.count == finalTargets.count
        }
        checks.expect(fixture.state.calls.count == 11 && fixture.state.maximumActive <= AppIconCache.maximumApplicationWorkers,
                      "Rapid result replacement drops every intermediate queued request and keeps actual concurrency bounded")
        checks.expect(Set(callbacks) == Set(finalTargets.map(\.id)) && cache.cachedApplicationCount == 9,
                      "Reindex discards stale decoded images and publishes only the newest generation")
        checks.expect(!fixture.state.onMain, "All application icon reads and decoding remain off the main thread")
        let images = finalTargets.map { cache.image(for: $0) }
        checks.expect(images.allSatisfy { $0 !== placeholder }, "Each visible application receives its decoded image")
        cache.prepare(finalTargets)
        checks.expect(finalTargets.enumerated().allSatisfy { cache.image(for: $0.element) === images[$0.offset] }
                      && fixture.state.calls.count == 11,
                      "Warm preparation and drawing keep image identity without starting additional work")

        for start in stride(from: 80, to: apps.count, by: 9) {
            let targets = Array(apps[start..<min(start + 9, apps.count)])
            let previousCount = callbacks.count
            cache.prepare(targets)
            await checks.eventually("A synthetic cache-capacity batch completes") {
                callbacks.count == previousCount + targets.count
            }
            checks.expect(cache.cachedApplicationCount <= AppIconCache.maximumApplicationImages,
                          "Browsing many applications never grows the decoded image cache beyond its cap")
        }
        // Add enough earlier, uncached targets to cross the cap.
        for start in stride(from: 10, to: 70, by: 9) {
            let targets = Array(apps[start..<min(start + 9, 70)])
            let previousCount = callbacks.count
            cache.prepare(targets)
            await checks.eventually("A synthetic cache-eviction batch completes") {
                callbacks.count == previousCount + targets.count
            }
        }
        checks.expect(cache.cachedApplicationCount == AppIconCache.maximumApplicationImages,
                      "Crossing the cache limit evicts old decoded images instead of retaining every visited application")
        let newest = Array(apps[64..<70])
        let newestImages = newest.map { cache.image(for: $0) }
        checks.expect(newest.enumerated().allSatisfy { cache.image(for: $0.element) === newestImages[$0.offset] },
                      "Eviction protects currently visible application icons")

        let closedFixture = ApplicationIconFixture(blockFirst: 2)
        let closed = AppIconCache(resolveBrowser: { _ in nil }, loadBrowserIcon: { _ in nil },
                                  loadApplicationIcon: { closedFixture.load($0) })
        closed.prepare(Array(apps.prefix(9)))
        await checks.eventually("Close fixture starts its two allowed reads") { closedFixture.state.calls.count == 2 }
        closed.prepare([])
        closedFixture.releaseBlockedReads()
        await checks.eventually("Closing drains already-started reads") { closed.cachedApplicationCount == 2 }
        checks.expect(closedFixture.state.calls.count == 2,
                      "Hiding the launcher drops queued icon work and finishes only unavoidable in-flight reads")
        print("Application icon stress: 42 rapid target changes/reindexes behind stalled reads; 2 concurrent decoders, 11 total decodes for the final 9 results; cache capped at 256 images.")
    }

    @MainActor
    private static func checkApplicationViewInvalidation(_ checks: IconChecks) async {
        let apps = (1...9).map { index in
            IndexedApplication(name: "Fixture \(index)",
                               url: URL(fileURLWithPath: "/Synthetic/Fixture\(index).app"))
        }
        let fixture = ApplicationIconFixture(blockFirst: 0)
        let cache = AppIconCache(resolveBrowser: { _ in nil }, loadBrowserIcon: { _ in nil },
                                 loadApplicationIcon: { fixture.load($0) })
        let model = LauncherModel(applications: apps, icons: cache)
        let view = LauncherView(model: model, onSubmit: {}, onCancel: {}, onSettings: {})
        let window = NSPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        guard let scroll = view.subviews.compactMap({ $0 as? NSScrollView }).first,
              let table = scroll.documentView as? NSTableView else {
            checks.expect(false, "The icon-invalidation fixture must expose its native table")
            return
        }
        let dataSource = CountingDataSource(view)
        table.dataSource = dataSource
        model.setQuery("fixture")
        window.setContentSize(NSSize(width: 640, height: view.preferredHeight))
        view.layoutSubtreeIfNeeded()
        for row in model.results.indices { _ = table.view(atColumn: 0, row: row, makeIfNecessary: true) }
        await checks.eventually("Synthetic application rows finish their first icon decode") {
            cache.cachedApplicationCount == apps.count
        }
        checks.expect(fixture.state.calls.count == apps.count,
                      "Native initial preparation decodes each visible synthetic application once")
        let originalImages = apps.map { cache.image(for: $0) }
        model.select(LauncherResult.application(apps[3]).id)
        let originalResults = model.results
        let selectedID = model.selectedID
        let revision = cache.revision
        dataSource.rowCountRequests = 0

        // A rebuilt index may contain exactly the same result values. Publishing
        // an unrelated availability change exercises this redraw boundary without
        // reading the real app inventory or toggling any actual network policy.
        cache.invalidate()
        model.setAllowsGPTNetwork(true)
        checks.expect(cache.revision == revision + 1 && model.results == originalResults
                      && model.query == "fixture" && model.selectedID == selectedID,
                      "Icon invalidation leaves the existing query, results, and keyboard selection unchanged")
        checks.expect(dataSource.rowCountRequests > 0,
                      "A changed icon revision reloads native rows even when their result values are identical")
        // Do not ask image(for:) to start work here: the view's preparation must
        // independently notice invalidation and request these fresh images.
        await checks.eventually("The unchanged visible applications are re-decoded after invalidation") {
            fixture.state.calls.count == apps.count * 2 && cache.cachedApplicationCount == apps.count
        }
        view.layoutSubtreeIfNeeded()
        for (row, result) in model.results.enumerated() {
            guard case .application(let app) = result,
                  let sourceIndex = apps.firstIndex(where: { $0.id == app.id }),
                  let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) as? NSTableCellView else {
                checks.expect(false, "Each synthetic application must retain its native row")
                continue
            }
            let replacement = cache.image(for: app)
            checks.expect(replacement !== originalImages[sourceIndex] && cell.imageView?.image === replacement,
                          "An unchanged application row replaces old artwork with its freshly decoded cache image")
        }
        dataSource.rowCountRequests = 0
        model.setAllowsGPTNetwork(false)
        checks.expect(cache.revision == revision + 1 && dataSource.rowCountRequests == 0
                      && fixture.state.calls.count == apps.count * 2,
                      "Unchanged icon revisions do not reload app-only rows or restart decoding on later availability notifications")
        checks.expect(!fixture.state.onMain && !window.isVisible,
                      "The native invalidation regression remains offscreen with all decodes off-main")
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
        await checks.eventually("The real view cache must finish background command rendering") { callbacks.count == commands.count }
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
    private static func checkBrowserCache(_ checks: IconChecks) async -> [(String, NSImage)] {
        let red = BrowserIconFixture.bitmap(red: 0.9, green: 0.1, blue: 0.1)
        let green = BrowserIconFixture.bitmap(red: 0.1, green: 0.8, blue: 0.2)
        let blue = BrowserIconFixture.bitmap(red: 0.1, green: 0.2, blue: 0.9)
        let browser = WebSearchBrowser(bundleIdentifier: "test.icon.green", name: "Green Browser")
        let missing = WebSearchBrowser(bundleIdentifier: "test.icon.missing", name: "Missing Browser")
        let undecodable = WebSearchBrowser(bundleIdentifier: "test.icon.undecodable", name: "Unreadable Icon")
        let defaultURL = URL(fileURLWithPath: "/Synthetic/RedBrowser.app")
        let namedURL = URL(fileURLWithPath: "/Synthetic/GreenBrowser.app")
        let replacementURL = URL(fileURLWithPath: "/Synthetic/BlueBrowser.app")
        let undecodableURL = URL(fileURLWithPath: "/Synthetic/UnreadableBrowser.app")
        let fixture = BrowserIconFixture()
        fixture.set(nil, url: defaultURL, bitmap: red)
        fixture.set(browser.id, url: namedURL, bitmap: green)
        fixture.set(undecodable.id, url: undecodableURL)
        let cache = AppIconCache(resolveBrowser: { fixture.resolve($0) }, loadBrowserIcon: { fixture.load($0) })
        await checks.eventually("Browser fixture's original search artwork must become ready") {
            cache.image(for: .googleSearch).representations.contains { ($0 as? NSBitmapImageRep)?.pixelsWide == 56 }
        }
        checks.expect(fixture.state.resolutions.isEmpty && fixture.state.decodes.isEmpty,
                      "Constructing a cache must not discover browser apps before configuration")
        let fallback = cache.image(for: .googleSearch)
        var callbacks: [String] = []
        var callbacksOnMain = true
        cache.onLoad = { id in callbacks.append(id); callbacksOnMain = callbacksOnMain && Thread.isMainThread }
        let browsers = [browser, missing, undecodable]
        let results: [LauncherResult] = [.googleSearch] + browsers.map { .googleSearchIn($0) }
        cache.prepareBrowserIcons(browsers)
        checks.expect(results.allSatisfy { cache.image(forWebSearch: $0) === fallback },
                      "Browser rows return the existing search artwork immediately while discovery runs")
        await checks.eventually("Configured browser badges and missing-image fallbacks must finish") {
            Set(callbacks) == Set(results.map(\.id))
        }
        let defaultImage = cache.image(forWebSearch: .googleSearch)
        let namedImage = cache.image(forWebSearch: .googleSearchIn(browser))
        checks.expect(defaultImage !== fallback && namedImage !== fallback && defaultImage !== namedImage,
                      "Default and named browsers receive distinct cached composed images")
        checks.expect(cache.image(forWebSearch: .googleSearchIn(missing)) === fallback
                      && cache.image(forWebSearch: .googleSearchIn(undecodable)) === fallback,
                      "Missing apps and failed icon decoding both retain the original Google-search fallback")
        checks.expect(callbacksOnMain && !fixture.state.onMain,
                      "Browser resolution and image loading stay off-main while ready callbacks run on-main")
        checks.expect(fixture.state.resolutions.count == 4 && fixture.state.decodes.count == 3,
                      "Initial preparation resolves configured targets once and decodes only resolved apps")
        for image in [defaultImage, namedImage] {
            let reps = image.representations.compactMap { $0 as? NSBitmapImageRep }
            checks.expect(image.size == NSSize(width: 28, height: 28) && !image.isTemplate
                          && Set(reps.map(\.pixelsWide)) == [28, 56]
                          && reps.allSatisfy { $0.pixelsWide == $0.pixelsHigh && $0.size == image.size },
                          "Browser composites retain colored 28-point ordinary and Retina representations")
        }
        let rendered = await Task.detached(priority: .userInitiated) {
            [1, 2].map { scale in
                (scale, AppIconCache.renderWebSearchBadge(red, scale: scale),
                 AppIconCache.renderWebSearchBadge(blue, scale: scale))
            }
        }.value
        for (scale, redImage, blueImage) in rendered {
            guard let redImage, let blueImage,
                  let redBytes = redImage.dataProvider?.data as Data?,
                  let blueBytes = blueImage.dataProvider?.data as Data? else {
                checks.expect(false, "Browser badges must compose at \(scale)x")
                continue
            }
            checks.expect(redImage.width == 28 * scale && redImage.height == 28 * scale && redBytes != blueBytes,
                          "Different browser artwork must produce distinguishable \(scale)x badges")
            let redRep = NSBitmapImageRep(cgImage: redImage)
            let blueRep = NSBitmapImageRep(cgImage: blueImage)
            var changedPixels = 0
            var leftChangedPixels = 0
            var topChangedPixels = 0
            for y in 0..<redImage.height {
                for x in 0..<redImage.width {
                    let lhs = redRep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                    let rhs = blueRep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                    let difference = abs((lhs?.redComponent ?? 0) - (rhs?.redComponent ?? 0))
                        + abs((lhs?.blueComponent ?? 0) - (rhs?.blueComponent ?? 0))
                    if difference > 0.1 {
                        changedPixels += 1
                        if x < 12 * scale { leftChangedPixels += 1 }
                        if y < 12 * scale { topChangedPixels += 1 }
                    }
                }
            }
            checks.expect(changedPixels > 40 * scale * scale && leftChangedPixels == 0 && topChangedPixels == 0,
                          "Changing the browser changes the lower-right badge while preserving the original upper-left search artwork at \(scale)x")
        }
        let beforeLookup = fixture.state
        let beforeCallbacks = callbacks.count
        var identityHits = 0
        var lookupSamples: [Double] = []
        for _ in 0..<100 {
            let start = DispatchTime.now().uptimeNanoseconds
            for _ in 0..<100 {
                if cache.image(forWebSearch: .googleSearch) === defaultImage { identityHits += 1 }
                if cache.image(forWebSearch: .googleSearchIn(browser)) === namedImage { identityHits += 1 }
            }
            lookupSamples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 200)
        }
        lookupSamples.sort()
        checks.expect(identityHits == 20_000 && fixture.state.resolutions == beforeLookup.resolutions
                      && fixture.state.decodes == beforeLookup.decodes && callbacks.count == beforeCallbacks,
                      "Browser lookups are pure cached reads without discovery, decoding, or callbacks")
        print(String(format: "Cached browser-badge lookup (100 batches): p50 %.1f ns/op; p95 %.1f; max batch average %.1f.",
                     lookupSamples[49], lookupSamples[94], lookupSamples[99]))
        cache.prepareBrowserIcons(browsers)
        checks.expect(fixture.state.resolutions == beforeLookup.resolutions,
                      "Reapplying unchanged browser targets must not schedule another discovery batch")
        cache.refreshBrowserIcons()
        await checks.eventually("An invocation refresh rechecks configured browser locations") {
            fixture.state.completed >= beforeLookup.completed + results.count
        }
        try? await Task.sleep(for: .milliseconds(25))
        checks.expect(cache.image(forWebSearch: .googleSearch) === defaultImage
                      && cache.image(forWebSearch: .googleSearchIn(browser)) === namedImage
                      && fixture.state.decodes == beforeLookup.decodes && callbacks.count == beforeCallbacks,
                      "Unchanged app locations preserve image identity, skip decoding, and publish no icon updates")
        fixture.set(nil, url: replacementURL, bitmap: blue)
        let beforeReplacement = fixture.state.decodes
        let beforeReplacementCallbacks = callbacks.count
        cache.refreshBrowserIcons()
        await checks.eventually("A changed system default replaces the default badge") {
            cache.image(forWebSearch: .googleSearch) !== defaultImage
        }
        let replacementImage = cache.image(forWebSearch: .googleSearch)
        checks.expect(cache.image(forWebSearch: .googleSearchIn(browser)) === namedImage
                      && Array(fixture.state.decodes.dropFirst(beforeReplacement.count)) == [replacementURL]
                      && Array(callbacks.dropFirst(beforeReplacementCallbacks)) == [LauncherResult.googleSearch.id],
                      "Changing the default browser decodes and updates only its own badge")
        let beforeReindexCallbacks = callbacks.count
        cache.invalidate()
        checks.expect(cache.image(forWebSearch: .googleSearch) === replacementImage
                      && cache.image(forWebSearch: .googleSearchIn(browser)) === namedImage,
                      "A manual reindex retains ready browser artwork while its refresh runs")
        await checks.eventually("Reindexing eventually refreshes configured browser artwork") {
            callbacks.count >= beforeReindexCallbacks + results.count
        }

        // Configuration changes while discovery is blocked must coalesce behind
        // one worker, with no publication from the superseded configuration.
        let staleFixture = BrowserIconFixture()
        staleFixture.set(nil, url: defaultURL, bitmap: red)
        staleFixture.set(browser.id, url: namedURL, bitmap: green)
        let newer = WebSearchBrowser(bundleIdentifier: "test.icon.newer", name: "Newer Browser")
        staleFixture.set(newer.id, url: replacementURL, bitmap: blue)
        let staleCache = AppIconCache(resolveBrowser: { staleFixture.resolve($0) }, loadBrowserIcon: { staleFixture.load($0) })
        await checks.eventually("Stale-generation fixture command images become ready") {
            staleCache.image(for: .googleSearch).representations.contains { ($0 as? NSBitmapImageRep)?.pixelsWide == 56 }
        }
        var staleCallbacks: [String] = []
        staleCache.onLoad = { staleCallbacks.append($0) }
        let gate = staleFixture.suspendNextResolution()
        staleCache.prepareBrowserIcons([browser])
        await checks.eventually("The first browser discovery worker is suspended") { staleFixture.state.resolutions.count == 1 }
        staleCache.prepareBrowserIcons([newer])
        for _ in 0..<20 { staleCache.refreshBrowserIcons() }
        try? await Task.sleep(for: .milliseconds(25))
        checks.expect(staleFixture.state.resolutions.count == 1 && staleFixture.state.maxActive == 1,
                      "Repeated refreshes and replacement targets must not accumulate workers behind a blocked lookup")
        gate.signal()
        await checks.eventually("Only the newest browser configuration becomes ready after a suspended batch") {
            staleCallbacks.contains(LauncherResult.googleSearchIn(newer).id)
        }
        checks.expect(!staleCallbacks.contains(LauncherResult.googleSearchIn(browser).id)
                      && staleCache.image(forWebSearch: .googleSearchIn(browser)) === staleCache.image(for: .googleSearch)
                      && staleFixture.state.maxActive == 1,
                      "Superseded browser work never publishes or restores removed choices")
        checks.expect(!staleFixture.state.onMain, "Coalescing stale browser work never moves discovery or decoding onto the main thread")
        return [("Default: red", defaultImage), ("Added: green", namedImage),
                ("New default: blue", replacementImage), ("Missing: fallback", fallback)]
    }

    @MainActor
    private static func checkBrowserView(_ checks: IconChecks) async {
        let browser = WebSearchBrowser(bundleIdentifier: "test.row.browser", name: "Row Browser")
        let removed = WebSearchBrowser(bundleIdentifier: "test.row.removed", name: "Removed Browser")
        let fixture = BrowserIconFixture()
        fixture.set(nil, url: URL(fileURLWithPath: "/Synthetic/RowDefault.app"),
                    bitmap: BrowserIconFixture.bitmap(red: 0.9, green: 0.1, blue: 0.1))
        fixture.set(browser.id, url: URL(fileURLWithPath: "/Synthetic/RowNamed.app"),
                    bitmap: BrowserIconFixture.bitmap(red: 0.1, green: 0.8, blue: 0.2))
        let cache = AppIconCache(resolveBrowser: { fixture.resolve($0) }, loadBrowserIcon: { fixture.load($0) })
        await checks.eventually("Browser row fixture command artwork becomes ready") {
            cache.image(for: .googleSearch).representations.contains { ($0 as? NSBitmapImageRep)?.pixelsWide == 56 }
        }
        let model = LauncherModel(icons: cache)
        model.setWebSearchPreferences(enabled: true, browsers: [browser])
        let view = LauncherView(model: model, onSubmit: {}, onCancel: {}, onSettings: {})
        let window = NSPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        guard let scroll = view.subviews.compactMap({ $0 as? NSScrollView }).first,
              let table = scroll.documentView as? NSTableView else {
            checks.expect(false, "Browser row fixture must expose the native results table")
            return
        }
        let dataSource = CountingDataSource(view)
        table.dataSource = dataSource
        model.setQuery("synthetic unmatched browser rows")
        model.showSearchBrowsers()
        model.select(LauncherResult.googleSearchIn(browser).id)
        window.setContentSize(NSSize(width: 640, height: view.preferredHeight))
        view.layoutSubtreeIfNeeded()
        window.makeFirstResponder(view.searchField)
        let cells = model.results.indices.compactMap { table.view(atColumn: 0, row: $0, makeIfNecessary: true) as? NSTableCellView }
        checks.expect(cells.count == 2, "The browser row fixture must display one default and one curated choice")
        let selection = model.selectedID
        let order = model.results
        let query = model.query
        let responder = window.firstResponder
        let tableSelection = table.selectedRow
        let rowUpdates = model.onChange
        var modelUpdates = 0
        model.onChange = { modelUpdates += 1; rowUpdates?() }
        let updateIcon = cache.onLoad
        var callbacks: [String] = []
        cache.onLoad = { callbacks.append($0); updateIcon?($0) }
        dataSource.rowCountRequests = 0
        let gate = fixture.suspendNextResolution()
        cache.prepareBrowserIcons([browser])
        await checks.eventually("Browser rows are visible while their icon resolver is suspended") { fixture.state.resolutions.count == 1 }
        checks.expect(cells.allSatisfy { $0.imageView?.image === cache.image(for: .googleSearch) },
                      "Unresolved browser rows reuse the existing search icon")
        gate.signal()
        await checks.eventually("Browser row callbacks update both configured images") { callbacks.count == 2 }
        checks.expect(modelUpdates == 0 && dataSource.rowCountRequests == 0 && model.query == query
                      && model.results == order && model.selectedID == selection,
                      "Browser icon completion must not reload the table, publish query state, or reorder selection")
        checks.expect(window.firstResponder === responder && table.selectedRow == tableSelection,
                      "Browser icon completion must preserve editing focus and native row selection")
        for (row, cell) in cells.enumerated() {
            checks.expect(table.view(atColumn: 0, row: row, makeIfNecessary: false) === cell
                          && cell.imageView?.image === cache.image(forWebSearch: order[row]),
                          "Each browser callback updates only its own existing row with the matching composite")
        }
        let readyImages = cells.map { $0.imageView?.image }
        cache.onLoad?(LauncherResult.googleSearchIn(removed).id)
        cache.onLoad?(LauncherResult.googleSearch.id)
        checks.expect(zip(cells, readyImages).allSatisfy { $0.0.imageView?.image === $0.1 }
                      && dataSource.rowCountRequests == 0 && modelUpdates == 0,
                      "A removed-browser callback and a default refresh cannot overwrite another browser's row")
        model.reset()
        let idleHeight = view.preferredHeight
        dataSource.rowCountRequests = 0
        cache.onLoad?(LauncherResult.googleSearchIn(browser).id)
        checks.expect(model.results.isEmpty && model.selectedID == nil && view.preferredHeight == idleHeight
                      && dataSource.rowCountRequests == 0,
                      "Browser callbacks after reset must keep the launcher empty and its compact size unchanged")
    }

    @MainActor
    private static func exportBrowserPreview(images: [(String, NSImage)], to url: URL) throws {
        let width = 148 * images.count
        guard let context = CGContext(data: nil, width: width, height: 392, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CheckError.preview }
        for (section, dark) in [true, false].enumerated() {
            let origin = CGFloat(section * 196)
            context.setFillColor(dark ? CGColor(red: 0.045, green: 0.065, blue: 0.105, alpha: 1) : CGColor(gray: 0.95, alpha: 1))
            context.fill(CGRect(x: 0, y: origin, width: CGFloat(width), height: 196))
            for (index, fixture) in images.enumerated() {
                let x = CGFloat(index * 148 + 18)
                let reps = fixture.1.representations.compactMap { $0 as? NSBitmapImageRep }
                guard let ordinary = reps.first(where: { $0.pixelsWide == 28 })?.cgImage,
                      let retina = reps.first(where: { $0.pixelsWide == 56 })?.cgImage else { throw CheckError.preview }
                context.draw(ordinary, in: CGRect(x: x, y: origin + 130, width: 28, height: 28))
                context.interpolationQuality = .high
                context.draw(retina, in: CGRect(x: x, y: origin + 10, width: 112, height: 112))
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: fixture.0, attributes: [
                    .font: NSFont.systemFont(ofSize: 11), .foregroundColor: dark ? NSColor.white : NSColor.black
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

/// Synthetic decoding with two deliberately stalled calls. Does not inspect
/// installed apps, Launch Services, or any user file.
private final class ApplicationIconFixture: @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private let blockFirst: Int
    private let bitmap = BrowserIconFixture.bitmap(red: 0.2, green: 0.5, blue: 0.8)
    private var calls: [URL] = []
    private var active = 0
    private var maximumActive = 0
    private var onMain = false

    init(blockFirst: Int) { self.blockFirst = blockFirst }

    func load(_ url: URL) -> CGImage? {
        lock.lock()
        calls.append(url)
        active += 1
        maximumActive = max(maximumActive, active)
        onMain = onMain || Thread.isMainThread
        let shouldBlock = calls.count <= blockFirst
        lock.unlock()
        if shouldBlock { _ = gate.wait(timeout: .now() + 5) }
        lock.lock()
        active -= 1
        lock.unlock()
        return bitmap
    }

    func releaseBlockedReads() {
        for _ in 0..<blockFirst { gate.signal() }
    }

    var state: (calls: [URL], maximumActive: Int, onMain: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (calls, maximumActive, onMain)
    }
}

/// Entirely synthetic browser discovery/decoding, including a single suspended
/// lookup for racing configuration changes without touching Launch Services.
private final class BrowserIconFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [String: URL] = [:]
    private var bitmaps: [URL: CGImage] = [:]
    private var nextGate: DispatchSemaphore?
    private var resolverCalls: [String] = []
    private var decoderCalls: [URL] = []
    private var activeResolvers = 0
    private var maximumActiveResolvers = 0
    private var completedResolvers = 0
    private var workOnMain = false

    func set(_ identifier: String?, url: URL?, bitmap: CGImage? = nil) {
        lock.lock()
        defer { lock.unlock() }
        urls[identifier ?? "<default>"] = url
        if let url, let bitmap { bitmaps[url] = bitmap }
    }

    func suspendNextResolution() -> DispatchSemaphore {
        lock.lock()
        defer { lock.unlock() }
        let gate = DispatchSemaphore(value: 0)
        nextGate = gate
        return gate
    }

    func resolve(_ identifier: String?) -> URL? {
        lock.lock()
        let key = identifier ?? "<default>"
        resolverCalls.append(key)
        workOnMain = workOnMain || Thread.isMainThread
        activeResolvers += 1
        maximumActiveResolvers = max(maximumActiveResolvers, activeResolvers)
        let result = urls[key]
        let gate = nextGate
        nextGate = nil
        lock.unlock()
        if let gate { _ = gate.wait(timeout: .now() + 5) }
        lock.lock()
        activeResolvers -= 1
        completedResolvers += 1
        lock.unlock()
        return result
    }

    func load(_ url: URL) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        decoderCalls.append(url)
        workOnMain = workOnMain || Thread.isMainThread
        return bitmaps[url]
    }

    var state: (resolutions: [String], decodes: [URL], completed: Int, maxActive: Int, onMain: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (resolverCalls, decoderCalls, completedResolvers, maximumActiveResolvers, workOnMain)
    }

    static func bitmap(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: 56, height: 56, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 56, height: 56))
        return context.makeImage()!
    }
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
