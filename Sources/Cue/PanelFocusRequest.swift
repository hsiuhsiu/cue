import AppKit

/// A nonactivating panel takes key focus without moving the foreground app.
/// Keep its one next-event check outside query rendering. Never retry after a
/// dismissal, a different foreground app, or a genuine key-window loss.
@MainActor
final class PanelFocusRequest {
    struct State {
        var isVisible: Bool
        var isKeyWindow: Bool
        var frontmostProcess: Int32?
    }

    private let processID: Int32
    private let state: () -> State
    private let orderAndFocus: () -> Void
    private let nextEvent: (@escaping @MainActor @Sendable () -> Void) -> Void
    private var generation = 0
    private struct Pending {
        let generation: Int
        let origin: Int32?
    }
    private var pending: Pending?

    init(processID: Int32, state: @escaping () -> State,
         orderAndFocus: @escaping () -> Void,
         nextEvent: @escaping (@escaping @MainActor @Sendable () -> Void) -> Void) {
        self.processID = processID
        self.state = state
        self.orderAndFocus = orderAndFocus
        self.nextEvent = nextEvent
    }

    var hasKeyboardFocus: Bool { ownsKeyboard(state()) }

    func present() {
        generation &+= 1
        let request = generation
        pending = Pending(generation: request, origin: state().frontmostProcess)
        // Use AppKit's panel focus mechanism without requesting the foreground
        // switch that a source app's Secure Input can reject.
        orderAndFocus()
        // A key-window notification may arrive after this callback. This is an
        // event-loop check, not a wait before accepting input.
        nextEvent { [weak self] in self?.checkAfterEvent(request) }
    }

    func foregroundApplicationChanged(to process: Int32) {
        guard let pending, process != processID, process != pending.origin else { return }
        cancel()
    }

    func cancel() {
        generation &+= 1
        pending = nil
    }

    private func checkAfterEvent(_ request: Int) {
        guard let pending, pending.generation == request else { return }
        let current = state()
        guard current.isVisible,
              let foreground = current.frontmostProcess,
              foreground == processID || foreground == pending.origin else {
            cancel()
            return
        }
        self.pending = nil
        if !ownsKeyboard(current) {
            orderAndFocus()
        }
    }

    private func ownsKeyboard(_ current: State) -> Bool {
        // The source intentionally remains frontmost. App activation is neither
        // necessary nor evidence of key focus for a nonactivating NSPanel.
        current.isVisible && current.isKeyWindow
    }
}
