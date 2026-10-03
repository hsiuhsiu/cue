import AppKit
import Carbon
import CueCore

@MainActor
private final class StreamFixture {
    struct Request {
        let input: String
        let mode: GPTMode
        let configuration: GPTConfiguration
        let delta: @MainActor (String) -> Void
        let completion: CheckedContinuation<Void, Error>
    }
    var requests: [Request] = []
    var cancelCount = 0
    func stream(_ input: String, _ mode: GPTMode, _ configuration: GPTConfiguration,
                _ delta: @escaping @MainActor (String) -> Void) async throws {
        try await withCheckedThrowingContinuation { completion in
            requests.append(Request(input: input, mode: mode, configuration: configuration,
                                    delta: delta, completion: completion))
        }
    }
    func finish(_ index: Int, error: Error? = nil) {
        if let error { requests[index].completion.resume(throwing: error) }
        else { requests[index].completion.resume() }
    }
}

@MainActor private final class ConfigurationFixture {
    var value = GPTConfiguration()
}

private actor CopyFixture {
    var pending: [CheckedContinuation<Void, Never>] = []
    private(set) var written: [String] = []
    private(set) var calls = 0
    private var shouldFail = false
    func fail(_ value: Bool) { shouldFail = value }
    func copy(_ value: String) async throws {
        calls += 1
        await withCheckedContinuation { pending.append($0) }
        try Task.checkCancellation()
        if shouldFail { throw CalculatorCopyService.Failure.writeFailed }
        written.append(value)
    }
    func resume() {
        let current = pending
        pending = []
        current.forEach { $0.resume() }
    }
}

@main
struct CheckGPTUI {
    @MainActor static var count = 0
    @MainActor static func check(_ value: Bool, _ message: String) {
        guard value else { print("FAIL: \(message)"); exit(1) }
        count += 1
    }
    @MainActor static func eventually(_ message: String, _ predicate: () async -> Bool) async {
        for _ in 0..<2_000 {
            if await predicate() { check(true, message); return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        check(false, message)
    }
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        NSApplication.shared.mainMenu = nil
        await checkLifecycle()
        await checkSettingsDetour()
        await checkCopy()
        await checkErrors()
        await checkView()
        print("GPT UI checks passed: \(count)")
    }

    @MainActor static func checkLifecycle() async {
        let fixture = StreamFixture()
        let config = ConfigurationFixture()
        let model = GPTModel(configuration: { config.value }, stream: fixture.stream,
                             cancelStream: { fixture.cancelCount += 1 })
        check(fixture.requests.isEmpty && model.status == .idle, "Constructing model performs no API work")
        model.open(input: "Hello\n世界", mode: .translate)
        check(model.isLoading && model.output.isEmpty, "Explicit action shows loading synchronously")
        await eventually("Explicit action starts one request") { fixture.requests.count == 1 }
        check(fixture.requests[0].input == "Hello\n世界" && fixture.requests[0].mode == .translate,
              "Input and requested mode survive multiline Unicode text")
        fixture.requests[0].delta("你好")
        check(model.output == "你好" && model.isLoading && !model.canCopy, "Streaming appears before completion and cannot copy an unfinished response")
        let oldGeneration = model.outputGeneration
        model.stop()
        check(model.status == .stopped && model.output == "你好" && model.canCopy, "Stop preserves explicitly marked partial response")
        fixture.requests[0].delta("STALE")
        fixture.finish(0)
        await Task.yield()
        check(model.output == "你好" && model.status == .stopped, "Late delta and completion after stop cannot mutate state")
        config.value.model = "custom-model"
        model.retry()
        await eventually("Manual retry starts another request") { fixture.requests.count == 2 }
        check(model.modelName == "custom-model" && fixture.requests[1].configuration.model == "custom-model",
              "Manual retry adopts current model preference")
        check(model.outputGeneration != oldGeneration && model.output.isEmpty, "Retry replaces prior partial response")
        model.close()
        fixture.requests[1].delta("PRIVATE")
        fixture.finish(1, error: GPTClientError.connection)
        await Task.yield()
        check(model.status == .idle && model.input.isEmpty && model.output.isEmpty && !model.isPresented,
              "Closing cancels work and clears ephemeral input/output even after late failures")
        model.retry()
        check(fixture.requests.count == 2, "A hidden page cannot retry")
        model.open(input: "old", mode: .answer)
        await eventually("Start request before superseding") { fixture.requests.count == 3 }
        model.open(input: "new", mode: .answer)
        await eventually("Superseding starts a new explicit request") { fixture.requests.count == 4 }
        fixture.requests[2].delta("OLD")
        fixture.finish(2)
        fixture.requests[3].delta("New answer")
        fixture.finish(3)
        await eventually("Current request completes") { model.status == .completed }
        check(model.input == "new" && model.output == "New answer", "Superseded request never contaminates latest answer")
        check(fixture.cancelCount >= 4, "All close/stop/supersede paths cancel underlying transport")
        model.close()
    }

    @MainActor static func checkSettingsDetour() async {
        let fixture = StreamFixture()
        let config = ConfigurationFixture()
        let writer = CopyFixture()
        let model = GPTModel(configuration: { config.value }, stream: fixture.stream,
                             cancelStream: { fixture.cancelCount += 1 },
                             copier: { try await writer.copy($0) })
        model.open(input: "Keep this original text\n保留原文", mode: .translate)
        await eventually("Settings fixture starts only on explicit use") { fixture.requests.count == 1 }
        fixture.requests[0].delta("Partial translation")
        model.suspendForSettings()
        check(!model.isPresented && model.status == .stopped && model.output == "Partial translation",
              "Settings stop transport without losing a partial reply")
        fixture.requests[0].delta("STALE")
        fixture.finish(0)
        config.value.model = "new-model"
        model.retry()
        await Task.yield()
        check(fixture.requests.count == 1 && model.output == "Partial translation",
              "Hidden settings context rejects late tokens and cannot retry")
        model.resumeAfterSettings()
        check(model.input == "Keep this original text\n保留原文" && model.mode == .translate && model.canCopy,
              "Returning restores the original input, direction, and marked partial reply")
        check(fixture.requests.count == 1, "Returning from settings never resubmits or incurs a new request")
        model.retry()
        await eventually("Explicit retry after settings starts a new request") { fixture.requests.count == 2 }
        check(fixture.requests[1].configuration.model == "new-model" && fixture.requests[1].input == model.input,
              "Retry uses updated settings with the same original text")
        fixture.requests[1].delta("Complete translation")
        fixture.finish(1)
        await eventually("Fixture completes") { model.status == .completed }
        model.copyResult()
        await eventually("Copy waits in isolated writer") { await writer.calls == 1 }
        model.suspendForSettings()
        await writer.resume()
        await Task.yield()
        check(await writer.written.isEmpty, "Entering settings cancels a pending copy before its write")
        model.resumeAfterSettings()
        check(model.status == .completed && model.output == "Complete translation",
              "Completed replies survive a settings detour without being relabeled incomplete")
        model.close()
        check(model.input.isEmpty && model.output.isEmpty, "Actual dismissal still clears all private text")
    }

    @MainActor static func checkCopy() async {
        let writer = CopyFixture()
        let model = GPTModel(configuration: { GPTConfiguration() }, stream: { _, _, _, delta in
            delta("第一行\nSecond line 👋🏽")
        }, copier: { try await writer.copy($0) })
        model.open(input: "translate this", mode: .translate)
        await eventually("Answer becomes copyable") { model.canCopy }
        model.copyResult()
        await eventually("Copy runs asynchronously") { await writer.calls == 1 }
        check(model.isCopying && !model.canCopy, "Repeated copy is disabled while pending")
        model.copyResult()
        model.close()
        await writer.resume()
        await Task.yield()
        check(await writer.written.isEmpty, "Closing before pasteboard publication cancels copy")
        model.open(input: "again", mode: .translate)
        await eventually("Reopened response completes") { model.canCopy }
        model.copyResult()
        await eventually("Reopened copy starts") { await writer.calls == 2 }
        await writer.resume()
        await eventually("Copy completion visible") { model.didCopy }
        check(await writer.written == ["第一行\nSecond line 👋🏽"], "Copy preserves exact multiline Unicode response")
        check(!model.isCopying && model.canCopy, "Completed copy restores button availability")
        await writer.fail(true)
        model.copyResult()
        await eventually("Failing copy starts") { await writer.calls == 3 }
        await writer.resume()
        await eventually("Clipboard error displayed") { model.errorMessage != nil }
        check(!model.didCopy, "Failed copy cannot report success")
        await writer.fail(false)
        model.copyResult()
        check(model.errorMessage == nil, "A new copy attempt clears the previous clipboard error")
        await eventually("Clipboard retry starts") { await writer.calls == 4 }
        await writer.resume()
        await eventually("Clipboard retry succeeds") { model.didCopy }
        check(model.errorMessage == nil, "Successful copy does not retain the earlier clipboard error")
        model.close()
    }

    @MainActor static func checkErrors() async {
        for error in [GPTClientError.networkDisabled, .missingAPIKey, .invalidInput, .invalidModel,
                      .authentication, .rateLimited, .modelUnavailable, .serviceUnavailable,
                      .invalidResponse, .incomplete, .refused, .connection, .keychain] {
            let model = GPTModel(configuration: { GPTConfiguration() }, stream: { _, _, _, _ in throw error })
            model.open(input: "test", mode: .answer)
            await eventually("Error reaches visible terminal status") { model.status == .failed }
            check(model.errorMessage == GPTText.shared.message(for: error), "Error is localized without exposing raw server details")
            model.close()
        }
        let model = GPTModel(configuration: { GPTConfiguration() }, stream: { _, _, _, delta in delta(" \n") })
        model.open(input: "test", mode: .answer)
        await eventually("An empty successful response is a clear error") { model.status == .failed }
        check(model.errorMessage == GPTText.shared.invalidResponse, "An empty result never appears successful")
        model.close()
    }

    @MainActor static func checkView() async {
        let fixture = StreamFixture()
        let model = GPTModel(configuration: { GPTConfiguration() }, stream: fixture.stream)
        let view = GPTView(model: model)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        var backCount = 0
        var settingsCount = 0
        view.onBack = { backCount += 1 }
        view.onSettings = { settingsCount += 1 }
        model.open(input: "Hello\n世界", mode: .answer)
        await eventually("View request starts") { fixture.requests.count == 1 }
        view.focusInput()
        let textView = descendants(view).compactMap { $0 as? NSTextView }.first!
        check(window.firstResponder === textView, "Entering page focuses selectable native response")
        check(!textView.isEditable && textView.isSelectable && !textView.isRichText && !textView.isAutomaticLinkDetectionEnabled,
              "Answers are inert, selectable plain text without remote-content rendering")
        fixture.requests[0].delta("First answer")
        check(textView.string == "First answer", "First delta renders immediately")
        textView.setSelectedRange(NSRange(location: 0, length: 5))
        fixture.requests[0].delta("\nMore")
        check(textView.string == "First answer\nMore", "Later delta appends to the response")
        check(textView.selectedRange() == NSRange(location: 0, length: 5), "Streaming preserves the reader’s selection")
        check(window.firstResponder === textView, "Streaming does not change first responder")
        check(!view.handleKeyEquivalent(key("c", code: UInt16(kVK_ANSI_C))), "Command-C with selected text retains native selection-copy behavior")
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        check(view.handleKeyEquivalent(key("c", code: UInt16(kVK_ANSI_C))), "Command-C without selection handles full-response copy")
        check(view.handleKeyEquivalent(key(",", code: UInt16(kVK_ANSI_Comma))) && settingsCount == 1,
              "Command-comma opens feature settings")
        check(view.handleKeyEquivalent(key(",", code: UInt16(kVK_ANSI_Comma), repeatKey: true)) && settingsCount == 1,
              "Held settings shortcut does not reopen the window repeatedly")
        check(view.handleKeyEquivalent(key("", code: UInt16(kVK_Escape), modifiers: [])) && backCount == 1,
              "Escape returns to launcher")
        check(view.handleKeyEquivalent(key("\r", code: UInt16(kVK_Return))), "Command-Return always handles the explicit copy shortcut")
        check(!view.handleKeyEquivalent(key("x", code: UInt16(kVK_ANSI_X))), "Unrelated keyboard shortcuts remain native")
        fixture.requests[0].delta(String(repeating: "\nA longer line keeps the response readable while streaming.", count: 30))
        view.layoutSubtreeIfNeeded()
        let scroll = descendants(view).compactMap { $0 as? NSScrollView }.first!
        check(textView.frame.height > scroll.contentSize.height, "Long answers remain accessible in the native scroll area")
        scroll.contentView.scroll(to: .zero)
        fixture.requests[0].delta("\nNEW TAIL")
        check(scroll.contentView.bounds.origin.y == 0, "A reader who scrolls upward is not pulled back to the streaming tail")
        fixture.finish(0)
        await eventually("View request finishes") { model.status == .completed }
        check(view.preferredHeight == 430, "Response pane keeps a compact stable height")
        model.close()
        check(textView.string.isEmpty, "Closing removes response text from the view")
        view.layoutSubtreeIfNeeded()
        check(textView.frame.height <= scroll.contentSize.height + 1, "Clearing a long answer resets its scroll document height")
        if let preview = ProcessInfo.processInfo.environment["CUE_GPT_UI_PREVIEW"] {
            model.open(input: "How do I keep a sourdough starter healthy?", mode: .answer)
            await eventually("Preview fixture starts") { fixture.requests.count == 2 }
            fixture.requests[1].delta("Feed it regularly with equal weights of starter, water, and flour. Keep it loosely covered.\n\n• Baking daily: leave it at room temperature and feed once or twice a day.\n• Baking weekly: refrigerate it and feed weekly.\n\nIt is ready to bake with when it doubles reliably and smells pleasantly tangy.")
            fixture.finish(1)
            await eventually("Preview fixture completes") { model.status == .completed }
            view.layoutSubtreeIfNeeded()
            if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: preview))
            }
            model.close()
        }
        window.contentView = nil
    }

    @MainActor static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
    @MainActor static func key(_ characters: String, code: UInt16,
                              modifiers: NSEvent.ModifierFlags = .command, repeatKey: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                        windowNumber: 0, context: nil, characters: characters,
                        charactersIgnoringModifiers: characters, isARepeat: repeatKey, keyCode: code)!
    }
}
