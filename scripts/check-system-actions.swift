import AppKit
import CueCore

/// Use the real views/controller with an injected action recorder. These checks
/// never sleep/lock the Mac, turn off displays, start pmset, show a window, post
/// keys, or read the clipboard.
@main
struct CheckSystemActions {
    @MainActor
    static func main() async {
        let application = NSApplication.shared
        application.setActivationPolicy(.prohibited)
        application.mainMenu = nil
        let checks = Checks()
        await checkScreenOffProcess(checks)
        do {
            try await checkRouting(checks)
            // Resolving the framework and symbol is safe; never call lock() here.
            _ = try LockScreenService()
            checks.expect(true, "The installed macOS must expose the lock-screen service")
        } catch {
            checks.expect(false, "Unexpected fixture or lock-service resolution failure: \(type(of: error))")
        }
        checks.expect(!application.isActive, "Checks must not activate their application")
        checks.expect(application.windows.allSatisfy { !$0.isVisible }, "Checks must never show a window")
        if !checks.failures.isEmpty {
            checks.failures.forEach { print("FAIL: \($0)") }
            print("System-action regression failed: \(checks.failures.count) failures / \(checks.count) checks.")
            exit(1)
        }
        print("System-action regression passed: \(checks.count) checks; English/Chinese commands, Enter and numbered routing, immediate dismissal, repeat suppression, display-sleep process validation, and lock-service availability. No real system action was performed.")
    }

    @MainActor
    private static func checkScreenOffProcess(_ checks: Checks) async {
        do {
            try await ScreenOffService.perform { executable, arguments in
                // A successful injected request proves both routing and executor;
                // the fixture never creates or launches a real Process.
                guard executable.path == "/usr/bin/pmset",
                      arguments == ["displaysleepnow"], !Thread.isMainThread else {
                    throw FixtureError.invalidInvocation
                }
                return 0
            }
            checks.expect(true, "Screen Off must use only the one-shot display-sleep command off the main thread")
        } catch {
            checks.expect(false, "The valid injected display-sleep request must succeed")
        }

        for status: Int32 in [-1, 1, 127] {
            do {
                try await ScreenOffService.perform { _, _ in status }
                checks.expect(false, "A nonzero display-sleep status must fail")
            } catch SystemActionError.screenOffFailed(let actual) {
                checks.expect(actual == status, "The display-sleep failure must retain its exit status")
            } catch {
                checks.expect(false, "A nonzero display-sleep status must produce the correct error")
            }
        }
        do {
            try await ScreenOffService.perform { _, _ in throw FixtureError.launchFailed }
            checks.expect(false, "A failed process launch must not report Screen Off success")
        } catch SystemActionError.screenOffUnavailable {
            checks.expect(true, "An unavailable display-sleep executable must produce a distinct launch error")
        } catch {
            checks.expect(false, "A process-launch failure must produce the correct error")
        }
    }

    private enum FixtureError: Error {
        case invalidInvocation
        case launchFailed
    }

    @MainActor
    private static func checkRouting(_ checks: Checks) async throws {
        let identifier = "com.yyhsiu.cue.tests.system-actions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: identifier)!
        // Registration is in-memory only; never alter the user's Cue preferences.
        defaults.register(defaults: ["clipboard.recordingEnabled": false])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(identifier, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let board = NSPasteboard(name: NSPasteboard.Name(identifier))
        precondition(board.name != .general)
        defer { board.releaseGlobally() }
        let clipboard = ClipboardModel(defaults: defaults, fileURL: directory.appendingPathComponent("history.json"),
                                       pasteboardName: board.name)
        defer { clipboard.close(); clipboard.stop() }
        checks.expect(!clipboard.recordingEnabled, "The isolated fixture must keep recording disabled")
        await checks.eventually("The isolated clipboard model must finish loading") { !clipboard.isLoading }

        let recorder = ActionRecorder()
        let controller = LauncherPanelController(clipboard: clipboard, performSystemAction: { action in
            await recorder.perform(action)
        })
        guard let window = NSApplication.shared.windows.last(where: { $0.contentView is LauncherView }),
              let view = window.contentView as? LauncherView else {
            checks.expect(false, "The controller must create its native launcher view offscreen")
            await clipboard.prepareForTermination()
            return
        }
        defer { window.contentView = nil; window.close() }
        checks.expect(!window.isVisible, "Constructing the controller must not open a window")
        let editor = NSTextView()
        let cases: [(String, LauncherResult, SystemAction)] = [
            ("sleep", .sleep, .sleep), ("睡眠", .sleep, .sleep),
            ("lock", .lockScreen, .lockScreen), ("鎖定", .lockScreen, .lockScreen),
            ("screen off", .screenOff, .screenOff), ("關閉螢幕", .screenOff, .screenOff),
        ]

        for (query, result, action) in cases {
            for route in ["Enter", "Command-1", "panel Command-1"] {
                controller.model.setQuery(query)
                checks.expect(controller.model.selectedResult == result,
                              "\(query) must immediately select the intended system command")
                let before = recorder.started.count
                let repeated = numberKey(window, repeated: true)
                checks.expect(view.handleNumberShortcut(repeated), "Repeated Command-1 must be consumed")
                await Task.yield()
                checks.expect(recorder.started.count == before && controller.model.query == query,
                              "Repeated Command-1 must not execute or dismiss a populated command")

                switch route {
                case "Enter":
                    checks.expect(view.control(view.searchField, textView: editor,
                                               doCommandBy: #selector(NSResponder.insertNewline(_:))),
                                  "Enter must be handled by the native search field")
                case "Command-1":
                    checks.expect(view.handleNumberShortcut(numberKey(window)),
                                  "Command-1 must be handled by the native launcher")
                default:
                    window.sendEvent(numberKey(window))
                }
                checks.expect(controller.model.query.isEmpty && controller.model.selectedResult == nil,
                              "\(route) for \(query) must reset the query before asynchronous work starts")
                checks.expect(!window.isVisible, "\(route) for \(query) must leave the panel closed")
                checks.expect(recorder.started.count == before,
                              "System work must not run synchronously inside keyboard dispatch")

                // Simulate held/repeated keys after dismissal while the action is pending.
                _ = view.handleNumberShortcut(repeated)
                _ = view.handleNumberShortcut(numberKey(window))
                _ = view.control(view.searchField, textView: editor,
                                 doCommandBy: #selector(NSResponder.insertNewline(_:)))
                await checks.eventually("\(route) for \(query) must dispatch exactly one injected action") {
                    recorder.started.count == before + 1
                }
                checks.expect(recorder.started.last == action, "\(query) must dispatch the correct system action")
                checks.expect(recorder.completed == before, "The action fixture must still be pending")
                controller.model.setQuery("Later typing remains responsive")
                checks.expect(controller.model.query == "Later typing remains responsive",
                              "An asynchronous system action must leave the model responsive")
                recorder.finish()
                await checks.eventually("The injected action must complete without reopening the panel") {
                    recorder.completed == before + 1
                }
                checks.expect(recorder.started.count == before + 1,
                              "Repeated or empty-query keys must not enqueue duplicate system actions")
                checks.expect(controller.model.query == "Later typing remains responsive" && !window.isVisible,
                              "A successful system action must not reset later typing or steal focus")
                controller.model.reset()
            }
        }
        await clipboard.prepareForTermination()
    }

    @MainActor
    private static func numberKey(_ window: NSWindow, repeated: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                        windowNumber: window.windowNumber, context: nil, characters: "1",
                        charactersIgnoringModifiers: "1", isARepeat: repeated, keyCode: 18)!
    }
}

@MainActor
private final class ActionRecorder {
    var started: [SystemAction] = []
    var completed = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func perform(_ action: SystemAction) async {
        started.append(action)
        await withCheckedContinuation { continuation = $0 }
        completed += 1
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class Checks {
    var count = 0
    var failures: [String] = []

    func expect(_ condition: Bool, _ message: String) {
        count += 1
        if !condition { failures.append(message) }
    }

    func eventually(_ message: String, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(10)) }
        expect(condition(), message)
    }
}
