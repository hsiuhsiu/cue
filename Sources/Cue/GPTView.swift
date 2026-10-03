import AppKit
import Carbon
import CueCore

struct GPTText {
    static let shared = GPTText()
    let answer = L10n.string("answer", table: "GPT", value: "Ask GPT")
    let translate = L10n.string("translate", table: "GPT", value: "GPT Translation")
    let back = L10n.string("back", table: "GPT", value: "Back to launcher (Esc)")
    let settings = L10n.string("settings", table: "GPT", value: "GPT Settings")
    let input = L10n.string("input", table: "GPT", value: "Your text")
    let response = L10n.string("response", table: "GPT", value: "GPT response")
    let loading = L10n.string("loading", table: "GPT", value: "Waiting for GPT…")
    let streaming = L10n.string("streaming", table: "GPT", value: "Receiving response…")
    let stopped = L10n.string("stopped", table: "GPT", value: "Stopped. The response may be incomplete.")
    let completed = L10n.string("completed", table: "GPT", value: "Response ready.")
    let translationCompleted = L10n.string("translation.completed", table: "GPT", value: "Translation ready.")
    let stop = L10n.string("stop", table: "GPT", value: "Stop")
    let retry = L10n.string("retry", table: "GPT", value: "Try Again")
    let copy = L10n.string("copy", table: "GPT", value: "Copy")
    let copyHelp = L10n.string("copy.help", table: "GPT", value: "Copy response (Command-Return)")
    let copying = L10n.string("copying", table: "GPT", value: "Copying…")
    let copied = L10n.string("copied", table: "GPT", value: "Copied")
    let networkDisabled = L10n.string("error.network", table: "GPT", value: "Cue’s network access is off. Enable it in Cue Settings to use GPT.")
    let missingAPIKey = L10n.string("error.key_missing", table: "GPT", value: "Add your OpenAI API key in GPT Settings to get started.")
    let invalidInput = L10n.string("error.input", table: "GPT", value: "Enter some text, or shorten it, then try again.")
    let invalidModel = L10n.string("error.model", table: "GPT", value: "Check the model name in GPT Settings.")
    let authentication = L10n.string("error.authentication", table: "GPT", value: "The API key wasn’t accepted. Update it in GPT Settings.")
    let rateLimited = L10n.string("error.rate_limit", table: "GPT", value: "API usage or rate limit reached. Check your OpenAI API account, then try again.")
    let modelUnavailable = L10n.string("error.model_unavailable", table: "GPT", value: "This model is unavailable for your API account. Choose another in GPT Settings.")
    let serviceUnavailable = L10n.string("error.service", table: "GPT", value: "GPT is temporarily unavailable. Try again later.")
    let invalidResponse = L10n.string("error.response", table: "GPT", value: "GPT didn’t return a usable response. Please try again.")
    let incomplete = L10n.string("error.incomplete", table: "GPT", value: "The response is incomplete. Shorten your question or try again.")
    let refused = L10n.string("error.refused", table: "GPT", value: "GPT couldn’t answer this request. Try rephrasing your text.")
    let connection = L10n.string("error.connection", table: "GPT", value: "Couldn’t connect to GPT. Check your connection and try again.")
    let keychain = L10n.string("error.keychain", table: "GPT", value: "Couldn’t read your API key from Keychain. Open GPT Settings to check it.")
    let copyError = L10n.string("error.copy", table: "GPT", value: "Couldn’t copy this response. Please try again.")
    let clipboardDenied = L10n.string("error.clipboard", table: "GPT", value: "Clipboard access is blocked. Allow Cue in System Settings, then try again.")

    func message(for error: Error) -> String {
        guard let error = error as? GPTClientError else { return connection }
        switch error {
        case .networkDisabled: return networkDisabled
        case .missingAPIKey: return missingAPIKey
        case .invalidInput: return invalidInput
        case .invalidModel: return invalidModel
        case .authentication: return authentication
        case .rateLimited: return rateLimited
        case .modelUnavailable: return modelUnavailable
        case .serviceUnavailable: return serviceUnavailable
        case .invalidResponse: return invalidResponse
        case .incomplete: return incomplete
        case .refused: return refused
        case .connection: return connection
        case .keychain: return keychain
        }
    }
}

private final class GPTResponseTextView: NSTextView {
    var onKeyEquivalent: ((NSEvent) -> Bool)?
    var onBack: (() -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyEquivalent?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if onKeyEquivalent?(event) == true { return }
        super.keyDown(with: event)
    }
    override func cancelOperation(_ sender: Any?) { onBack?() }
}

/// Plain selectable text: response content cannot execute code or fetch embedded remote resources.
@MainActor
final class GPTView: NSView {
    private let model: GPTModel
    private let text = GPTText.shared
    private let backdrop = LauncherBackdrop()
    private let backButton = NSButton()
    private let titleLabel = NSTextField(labelWithString: "")
    private let modelLabel = NSTextField(labelWithString: "")
    private let settingsButton = NSButton()
    private let inputLabel = NSTextField(wrappingLabelWithString: "")
    private let separator = NSBox()
    private let scroll = NSScrollView()
    private let responseText = GPTResponseTextView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let progress = NSProgressIndicator()
    private let footerSeparator = NSBox()
    private let retryButton = NSButton()
    private let stopButton = NSButton()
    private let copyButton = NSButton()
    private var displayedGeneration = -1
    private var displayedRevision = -1
    private var displayedInput = ""
    private var displayedLoading = false
    var onBack: (() -> Void)?
    var onSettings: (() -> Void)?
    var onPreferredHeightChange: ((CGFloat) -> Void)?
    var preferredHeight: CGFloat { 430 }
    override var isFlipped: Bool { true }

    init(model: GPTModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 430))
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        addSubview(backdrop)
        configureButton(backButton, title: "esc", action: #selector(goBack))
        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
        backButton.imagePosition = .imageLeft
        backButton.toolTip = text.back
        backButton.setAccessibilityLabel(text.back)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        modelLabel.font = .systemFont(ofSize: 11)
        modelLabel.textColor = .secondaryLabelColor
        modelLabel.alignment = .right
        modelLabel.lineBreakMode = .byTruncatingTail
        configureButton(settingsButton, title: "", action: #selector(openSettings))
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: text.settings)
        settingsButton.toolTip = text.settings
        settingsButton.setAccessibilityLabel(text.settings)
        inputLabel.font = .systemFont(ofSize: 16, weight: .medium)
        inputLabel.maximumNumberOfLines = 2
        inputLabel.lineBreakMode = .byTruncatingTail
        inputLabel.setAccessibilityLabel(text.input)
        separator.boxType = .separator
        footerSeparator.boxType = .separator
        responseText.isEditable = false
        responseText.isSelectable = true
        responseText.isRichText = false
        responseText.drawsBackground = false
        responseText.font = .systemFont(ofSize: 16)
        responseText.textColor = .labelColor
        responseText.textContainerInset = NSSize(width: 0, height: 4)
        responseText.textContainer?.lineFragmentPadding = 0
        responseText.textContainer?.widthTracksTextView = true
        responseText.isVerticallyResizable = true
        responseText.isHorizontallyResizable = false
        responseText.minSize = .zero
        responseText.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        responseText.autoresizingMask = .width
        responseText.isAutomaticLinkDetectionEnabled = false
        responseText.isAutomaticDataDetectionEnabled = false
        responseText.isAutomaticSpellingCorrectionEnabled = false
        responseText.isContinuousSpellCheckingEnabled = false
        responseText.isGrammarCheckingEnabled = false
        responseText.usesFindBar = false
        responseText.setAccessibilityLabel(text.response)
        responseText.onKeyEquivalent = { [weak self] in self?.handleKeyEquivalent($0) ?? false }
        responseText.onBack = { [weak self] in self?.onBack?() }
        scroll.documentView = responseText
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.horizontalScrollElasticity = .none
        scroll.automaticallyAdjustsContentInsets = false
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 3
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        configureButton(retryButton, title: text.retry, action: #selector(retry))
        configureButton(stopButton, title: text.stop, action: #selector(stop))
        configureButton(copyButton, title: text.copy + "  ⌘↵", action: #selector(copyResponse))
        copyButton.toolTip = text.copyHelp
        copyButton.setAccessibilityLabel(text.copyHelp)
        for child in [backButton, titleLabel, modelLabel, settingsButton, inputLabel, separator, scroll,
                      statusLabel, progress, footerSeparator, retryButton, stopButton, copyButton] {
            addSubview(child)
        }
        model.onChange = { [weak self] in self?.render() }
        render()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
        backButton.frame = NSRect(x: 10, y: 7, width: 58, height: 27)
        titleLabel.frame = NSRect(x: 78, y: 12, width: max(0, bounds.width - 330), height: 21)
        modelLabel.frame = NSRect(x: max(0, bounds.width - 242), y: 14, width: 188, height: 18)
        settingsButton.frame = NSRect(x: bounds.width - 43, y: 7, width: 32, height: 27)
        inputLabel.frame = NSRect(x: 16, y: 46, width: max(0, bounds.width - 32), height: 46)
        separator.frame = NSRect(x: 0, y: 102, width: bounds.width, height: 1)
        scroll.frame = NSRect(x: 16, y: 112, width: max(0, bounds.width - 32), height: max(0, bounds.height - 203))
        responseText.setFrameSize(NSSize(width: scroll.contentSize.width, height: max(responseText.frame.height, scroll.contentSize.height)))
        progress.frame = NSRect(x: 16, y: bounds.height - 77, width: 14, height: 14)
        statusLabel.frame = NSRect(x: model.isLoading ? 38 : 16, y: bounds.height - 79,
                                   width: max(0, bounds.width - (model.isLoading ? 54 : 32)), height: 39)
        footerSeparator.frame = NSRect(x: 0, y: bounds.height - 37, width: bounds.width, height: 1)
        retryButton.frame = NSRect(x: 10, y: bounds.height - 32, width: 102, height: 27)
        stopButton.frame = retryButton.frame
        copyButton.frame = NSRect(x: bounds.width - 136, y: bounds.height - 32, width: 125, height: 27)
    }

    /// Called only when entering this page, never as tokens arrive.
    func focusInput() { window?.makeFirstResponder(responseText) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleKeyEquivalent(event) || super.performKeyEquivalent(with: event)
    }

    func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers.isEmpty, event.keyCode == UInt16(kVK_Escape) {
            if !event.isARepeat { onBack?() }
            return true
        }
        guard modifiers == .command else { return false }
        if event.charactersIgnoringModifiers == "," || event.keyCode == UInt16(kVK_ANSI_Comma) {
            if !event.isARepeat { onSettings?() }
            return true
        }
        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            if !event.isARepeat { model.copyResult() }
            return true
        }
        if event.charactersIgnoringModifiers?.lowercased() == "c", responseText.selectedRange().length == 0 {
            if !event.isARepeat { model.copyResult() }
            return true
        }
        return false
    }

    override func cancelOperation(_ sender: Any?) { onBack?() }

    private func configureButton(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.bezelStyle = .rounded
        button.target = self
        button.action = action
    }

    private func render() {
        let title = model.mode == .translate ? text.translate : text.answer
        if titleLabel.stringValue != title { titleLabel.stringValue = title }
        if modelLabel.stringValue != model.modelName { modelLabel.stringValue = model.modelName }
        if displayedInput != model.input {
            displayedInput = model.input
            inputLabel.stringValue = model.input
        }
        updateResponse()
        let status: String
        if let error = model.errorMessage { status = error }
        else if model.didCopy { status = text.copied }
        else if model.isCopying { status = text.copying }
        else {
            switch model.status {
            case .idle: status = ""
            case .loading: status = model.output.isEmpty ? text.loading : text.streaming
            case .stopped: status = text.stopped
            case .completed: status = model.mode == .translate ? text.translationCompleted : text.completed
            case .failed: status = text.invalidResponse
            }
        }
        if statusLabel.stringValue != status {
            statusLabel.stringValue = status
            statusLabel.toolTip = status
        }
        if displayedLoading != model.isLoading {
            displayedLoading = model.isLoading
            if model.isLoading { progress.startAnimation(nil) }
            else { progress.stopAnimation(nil) }
            needsLayout = true
        }
        stopButton.isHidden = !model.isLoading
        retryButton.isHidden = model.isLoading || model.status == .idle
        copyButton.isEnabled = model.canCopy
    }

    private func updateResponse() {
        guard displayedGeneration != model.outputGeneration || displayedRevision != model.outputRevision else { return }
        let previousVisibleRect = scroll.contentView.bounds
        let wasNearBottom = previousVisibleRect.maxY >= responseText.bounds.maxY - 24
        let hadSelection = responseText.selectedRange().length > 0
        let newRequest = displayedGeneration != model.outputGeneration
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.labelColor]
        if !newRequest, model.outputRevision == displayedRevision + 1 {
            responseText.textStorage?.append(NSAttributedString(string: model.latestDelta, attributes: attributes))
        } else {
            responseText.textStorage?.setAttributedString(NSAttributedString(string: model.output, attributes: attributes))
        }
        displayedGeneration = model.outputGeneration
        displayedRevision = model.outputRevision
        if let container = responseText.textContainer { responseText.layoutManager?.ensureLayout(for: container) }
        if newRequest {
            responseText.setSelectedRange(NSRange(location: 0, length: 0))
            scroll.contentView.scroll(to: .zero)
        } else if wasNearBottom && !hadSelection {
            // Follow an answer only while the reader is already at the bottom. Never move a selection.
            let bottom = max(0, responseText.bounds.height - scroll.contentSize.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
        }
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    @objc private func goBack() { onBack?() }
    @objc private func openSettings() { onSettings?() }
    @objc private func retry() { model.retry() }
    @objc private func stop() { model.stop() }
    @objc private func copyResponse() { model.copyResult() }
}
