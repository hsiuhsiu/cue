import AppKit
import CueCore

/// Native views and injected metadata only: no windows, real file index, app
/// inventory, clipboard, preferences, credentials, or network requests.
@MainActor
private final class InteractionFileSearch: FileSearching {
    private var completion: (@MainActor (FileSearchResponse) -> Void)?
    private(set) var requestCount = 0

    func search(_ term: String, limit: Int, completion: @escaping @MainActor (FileSearchResponse) -> Void) {
        requestCount += 1
        self.completion = completion
    }

    func cancel() { completion = nil }

    func finish(_ files: [FileSearchResult]) {
        guard let callback = completion else { preconditionFailure("Expected a synthetic metadata request") }
        completion = nil
        callback(FileSearchResponse(results: files, error: nil))
    }
}

@main
private struct InteractionBenchmark {
    static func milliseconds(since start: UInt64) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    static func summary(_ samples: [Double]) -> [String: Double] {
        let sorted = samples.sorted()
        func percentile(_ fraction: Double) -> Double {
            sorted[min(sorted.count - 1, max(0, Int(ceil(Double(sorted.count) * fraction)) - 1))]
        }
        return ["p50_ms": percentile(0.5), "p95_ms": percentile(0.95),
                "p99_ms": percentile(0.99), "max_ms": sorted.last!]
    }

    @MainActor
    static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    @MainActor
    static func main() throws {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.mainMenu = nil
        let fixture = InteractionFileSearch()
        let icons = AppIconCache(resolveBrowser: { _ in nil }, loadBrowserIcon: { _ in nil })
        let model = LauncherModel(fileSearch: fixture, icons: icons)
        let view = LauncherView(model: model, onSubmit: {}, onCancel: {}, onSettings: {})
        let table = descendants(view).compactMap { $0 as? NSTableView }.first!
        let files = (1...9).map { index in
            FileSearchResult(url: URL(fileURLWithPath: "/Synthetic/Documents/report-\(index).txt"),
                             name: "report-\(index).txt", parentPath: "/Synthetic/Documents", isDirectory: false)
        }
        var heightChanges = 0
        var notifications = 0
        let render = model.onChange
        model.onChange = { notifications += 1; render?() }
        view.onPreferredHeightChange = { [weak view] height in
            guard let view, view.frame.height != height else { return }
            heightChanges += 1
            view.setFrameSize(NSSize(width: 640, height: height))
        }

        func layout() {
            view.layoutSubtreeIfNeeded()
            // Materialize the same nine native cells even with no NSWindow. This
            // includes row configuration/layout, not OS display composition.
            for row in 0..<table.numberOfRows {
                table.view(atColumn: 0, row: row, makeIfNecessary: true)?.layoutSubtreeIfNeeded()
            }
        }

        model.setQuery("f re")
        fixture.finish(files)
        layout()
        precondition(model.results.count == files.count && table.numberOfRows == files.count)
        heightChanges = 0
        notifications = 0
        var inputTimings: [Double] = []
        var completionTimings: [Double] = []
        var clearedMatchingResults = 0
        let initialRequests = fixture.requestCount
        for index in 0..<100 {
            let query = index.isMultiple(of: 2) ? "f r" : "f re"
            var started = DispatchTime.now().uptimeNanoseconds
            model.setQuery(query)
            layout()
            inputTimings.append(milliseconds(since: started))
            if model.results.isEmpty { clearedMatchingResults += 1 }

            started = DispatchTime.now().uptimeNanoseconds
            fixture.finish(files)
            layout()
            completionTimings.append(milliseconds(since: started))
            precondition(model.results.count == files.count && table.numberOfRows == files.count)
        }
        let fileHeightChanges = heightChanges
        let fileNotifications = notifications
        let fileRequests = fixture.requestCount - initialRequests
        precondition(fileRequests == 100)

        // The callbacks mirror the controller's cancellation/status cleanup.
        // Counts are reported rather than asserted so the identical harness can
        // compare old and optimized model implementations.
        func notificationCase(error: Bool, action: Bool) -> Int {
            model.onQueryChange = nil
            model.launchError = nil
            model.actionStatus = nil
            model.setQuery("f re")
            // The seed may already be the current query with no new request.
            // Existing results are sufficient; the next distinct edit is timed.
            if error { model.launchError = "Synthetic launch failure" }
            if action { model.actionStatus = "Synthetic operation" }
            model.onQueryChange = { [weak model] in model?.actionStatus = nil }
            notifications = 0
            model.setQuery("f r")
            let count = notifications
            fixture.finish(files)
            layout()
            return count
        }
        let notificationCounts = [
            "plain_query_edit": notificationCase(error: false, action: false),
            "clear_launch_error": notificationCase(error: true, action: false),
            "clear_action_in_onQueryChange": notificationCase(error: false, action: true),
            "clear_error_and_action_in_onQueryChange": notificationCase(error: true, action: true),
        ]
        model.onQueryChange = nil
        model.reset()
        precondition(!application.isActive && application.windows.isEmpty && view.window == nil)
        let output: [String: Any] = [
            "build": "swiftc -O, Swift 6",
            "fixture": "9 synthetic report-#.txt results; alternating f r / f re",
            "edits": 100,
            "file_requests": fileRequests,
            "setQuery_and_native_layout": summary(inputTimings),
            "completion_and_native_layout": summary(completionTimings),
            "matching_results_cleared_while_waiting": clearedMatchingResults,
            "preferred_height_changes": fileHeightChanges,
            "model_notifications_during_file_phases": fileNotifications,
            "model_notifications_per_query_edit": notificationCounts,
            "timing_scope": "Warm native view; main-actor query/completion + row configuration/layout. No Spotlight latency, input delivery, pixels, visible windows, or app activation.",
        ]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
