import AppKit
import Carbon
import CueCore

struct ClipboardText {
    static let shared = ClipboardText()

    let title = L10n.string("title", table: "Clipboard", value: "Clipboard History")
    let back = L10n.string("back", table: "Clipboard", value: "Back to launcher")
    let backHelp = L10n.string("back.help", table: "Clipboard", value: "Back to launcher (Esc)")
    let backToHistory = L10n.string("back.history", table: "Clipboard", value: "Back to clipboard history (Esc)")
    let searchPlaceholder = L10n.string("search.placeholder", table: "Clipboard", value: "Search clipboard history…")
    let searchAccessibility = L10n.string("search.accessibility", table: "Clipboard", value: "Search clipboard history")
    let resultsAccessibility = L10n.string("results.accessibility", table: "Clipboard", value: "Clipboard history")
    let loading = L10n.string("loading", table: "Clipboard", value: "Loading clipboard history…")
    let noResults = L10n.string("results.empty", table: "Clipboard", value: "Nothing matches your search.")
    let noHistory = L10n.string("history.empty", table: "Clipboard", value: "Copy text or a link to see it here.")
    let enableDescription = L10n.string("recording.introduction", table: "Clipboard", value: "Save text and links on this Mac.\nRecording starts only when you enable it.")
    let enable = L10n.string("recording.enable", table: "Clipboard", value: "Enable Clipboard History")
    let recording = L10n.string("recording.active", table: "Clipboard", value: "Recording · Text and links only")
    let paused = L10n.string("recording.paused", table: "Clipboard", value: "Recording is off")
    let copy = L10n.string("copy", table: "Clipboard", value: "Copy")
    let copyHelp = L10n.string("copy.help", table: "Clipboard", value: "Copy selected item (Return)")
    let copiedAt = L10n.string("copied_at", table: "Clipboard", value: "Copied %@")
    let delete = L10n.string("delete", table: "Clipboard", value: "Delete")
    let deleteHelp = L10n.string("delete.help", table: "Clipboard", value: "Delete selected item (Delete when search is empty, or ⌘⌫)")
    let settings = L10n.string("settings.title", table: "Clipboard", value: "Clipboard Settings")
    let settingsHelp = L10n.string("settings.help", table: "Clipboard", value: "Clipboard settings (⌘,)")
    let recordHistory = L10n.string("settings.recording", table: "Clipboard", value: "Record clipboard history")
    let retainFor = L10n.string("settings.retention", table: "Clipboard", value: "Keep history for")
    let hour = L10n.string("retention.hour", table: "Clipboard", value: "1 hour")
    let day = L10n.string("retention.day", table: "Clipboard", value: "1 day")
    let week = L10n.string("retention.week", table: "Clipboard", value: "7 days")
    let month = L10n.string("retention.month", table: "Clipboard", value: "30 days")
    let forever = L10n.string("retention.forever", table: "Clipboard", value: "No time limit")
    let localOnly = L10n.string("settings.local_only", table: "Clipboard", value: "Only text and links are saved on this Mac.")
    let expires = L10n.string("settings.expires", table: "Clipboard", value: "Older items are deleted automatically.")
    let noExpiry = L10n.string("settings.no_expiry", table: "Clipboard", value: "Items do not expire by time.")
    let capacity = L10n.string("settings.capacity", table: "Clipboard", value: "History keeps up to 500 items or 4 MiB; the oldest items are removed when full.")
}

private final class ClipboardResultsTable: NSTableView {
    override var acceptsFirstResponder: Bool { false }
}

private final class ClipboardResultRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        LauncherAppearance.selection.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 8, yRadius: 8).fill()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

private final class ClipboardResultCell: NSTableCellView {
    let preview = NSTextField(labelWithString: "")
    let timestamp = NSTextField(labelWithString: "")
    let number = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        preview.font = .systemFont(ofSize: 14)
        preview.lineBreakMode = .byTruncatingTail
        timestamp.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        timestamp.textColor = .secondaryLabelColor
        timestamp.lineBreakMode = .byTruncatingTail
        number.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        number.textColor = .secondaryLabelColor
        number.alignment = .right
        addSubview(preview)
        addSubview(timestamp)
        addSubview(number)
        textField = preview
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        preview.frame = NSRect(x: 8, y: 20, width: max(0, bounds.width - 76), height: 20)
        timestamp.frame = NSRect(x: 8, y: 3, width: max(0, bounds.width - 76), height: 16)
        number.frame = NSRect(x: bounds.width - 56, y: 13, width: 46, height: 18)
    }
}

/// A separate feature page with the same direct keyboard path as the launcher.
@MainActor
final class ClipboardView: NSView, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let searchField = NSTextField()
    private let model: ClipboardModel
    private let onCopy: (Int?) -> Void
    private let onBack: () -> Void
    private let text = ClipboardText.shared
    private let deleteTitle = ClipboardText.shared.delete + "  ⌫"
    private let filteredDeleteTitle = ClipboardText.shared.delete + "  ⌘⌫"
    private let material = LauncherBackdrop()
    private let backButton = NSButton()
    private let heading = NSTextField(labelWithString: "")
    private let searchIcon = NSImageView()
    private let separator = NSBox()
    private let table = ClipboardResultsTable()
    private let scroll = NSScrollView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let enableButton = NSButton()
    private let footerSeparator = NSBox()
    private let footer = NSTextField(labelWithString: "")
    private let copyButton = NSButton()
    private let deleteButton = NSButton()
    private let settingsButton = NSButton()
    private var settingsView: ClipboardSettingsView?
    private var displayedResults: [ClipboardEntry] = []
    private var displayedQuery = ""
    private var isUpdating = false
    var onPreferredHeightChange: ((CGFloat) -> Void)?
    private var lastPreferredHeight: CGFloat = 220
    var preferredHeight: CGFloat {
        if isShowingSettings { return 326 }
        return displayedResults.isEmpty ? 220 : 124 + CGFloat(min(displayedResults.count, 9)) * 46
    }
    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    override var isFlipped: Bool { true }
    private(set) var isShowingSettings = false

    init(model: ClipboardModel, onCopy: @escaping (Int?) -> Void, onBack: @escaping () -> Void) {
        self.model = model
        self.onCopy = onCopy
        self.onBack = onBack
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 220))
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        addSubview(material)

        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
        backButton.title = "esc"
        backButton.imagePosition = .imageLeft
        backButton.bezelStyle = .rounded
        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.toolTip = text.backHelp
        backButton.setAccessibilityLabel(text.back)
        heading.stringValue = text.title
        heading.font = .systemFont(ofSize: 14, weight: .semibold)
        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        searchIcon.contentTintColor = .secondaryLabelColor
        searchField.placeholderString = text.searchPlaceholder
        searchField.font = .systemFont(ofSize: 21)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.usesSingleLineMode = true
        searchField.delegate = self
        searchField.setAccessibilityLabel(text.searchAccessibility)
        separator.boxType = .separator
        footerSeparator.boxType = .separator

        table.headerView = nil
        table.style = .plain
        table.autoresizingMask = [.width]
        table.backgroundColor = .clear
        table.rowHeight = 44
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.selectionHighlightStyle = .regular
        table.focusRingType = .none
        table.allowsEmptySelection = true
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(doubleClickResult)
        table.setAccessibilityLabel(text.resultsAccessibility)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clipboard"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        scroll.documentView = table
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .none
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 14)
        enableButton.title = text.enable
        enableButton.bezelStyle = .rounded
        enableButton.target = self
        enableButton.action = #selector(enableRecording)

        footer.font = .systemFont(ofSize: 11)
        footer.lineBreakMode = .byTruncatingTail
        copyButton.title = text.copy + "  ↵"
        copyButton.bezelStyle = .rounded
        copyButton.target = self
        copyButton.action = #selector(copySelected)
        copyButton.toolTip = text.copyHelp
        copyButton.setAccessibilityLabel(text.copyHelp)
        deleteButton.title = deleteTitle
        deleteButton.bezelStyle = .rounded
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelected)
        deleteButton.toolTip = text.deleteHelp
        deleteButton.setAccessibilityLabel(text.deleteHelp)
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settingsButton.isBordered = false
        settingsButton.target = self
        settingsButton.action = #selector(openSettings)
        settingsButton.toolTip = text.settings
        settingsButton.setAccessibilityLabel(text.settings)
        for view in [backButton, heading, searchIcon, searchField, separator, scroll,
                     emptyLabel, enableButton, footerSeparator, footer, copyButton,
                     deleteButton, settingsButton] { addSubview(view) }
        model.onChange = { [weak self] in self?.render() }
        render()
        layoutSubtreeIfNeeded()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        material.frame = bounds
        backButton.frame = NSRect(x: 10, y: 5, width: 58, height: 26)
        heading.frame = NSRect(x: 80, y: 9, width: max(0, bounds.width - 94), height: 21)
        searchIcon.frame = NSRect(x: 14, y: 45, width: 20, height: 20)
        searchField.frame = NSRect(x: 42, y: 39, width: max(0, bounds.width - 56), height: 32)
        separator.frame = NSRect(x: 0, y: isShowingSettings ? 36 : 78, width: bounds.width, height: 1)
        scroll.frame = NSRect(x: 6, y: 84, width: bounds.width - 12, height: max(0, bounds.height - 124))
        scroll.layoutSubtreeIfNeeded()
        table.tableColumns.first?.width = scroll.contentSize.width
        let bodyMidY = 84 + max(0, bounds.height - 124) / 2
        emptyLabel.frame = NSRect(x: 20, y: bodyMidY - (enableButton.isHidden ? 18 : 48), width: max(0, bounds.width - 40), height: 36)
        enableButton.frame = NSRect(x: bounds.midX - 120, y: bodyMidY + 2, width: 240, height: 30)
        footerSeparator.frame = NSRect(x: 0, y: bounds.height - 34, width: bounds.width, height: 1)
        footer.frame = NSRect(x: 12, y: bounds.height - 25, width: max(0, bounds.width - (isShowingSettings ? 62 : 282)), height: 18)
        copyButton.frame = NSRect(x: bounds.width - 250, y: bounds.height - 30, width: 94, height: 26)
        deleteButton.frame = NSRect(x: bounds.width - 148, y: bounds.height - 30, width: 104, height: 26)
        settingsButton.frame = NSRect(x: bounds.width - 33, y: bounds.height - 29, width: 24, height: 24)
        let settingsWidth = min(536, bounds.width - 24)
        settingsView?.frame = NSRect(x: (bounds.width - settingsWidth) / 2, y: 44, width: settingsWidth, height: 248)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleSettingsShortcut(event) { return true }
        if handleNumberShortcut(event) { return true }
        if handleDeleteShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    func handleNumberShortcut(_ event: NSEvent) -> Bool {
        guard let index = ResultShortcut.index(for: event), !hasMarkedText, !isShowingSettings else { return false }
        if !event.isARepeat { onCopy(index) }
        return true
    }

    func handleDeleteShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, !hasMarkedText, !isShowingSettings,
              event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete)
        else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard modifiers == .command ||
                (modifiers.isEmpty && searchField.stringValue.isEmpty && model.query.isEmpty)
        else { return false }
        // A held Backspace may have just erased the last search character. Consume
        // repeats so it cannot continue through history after clearing the query.
        if !event.isARepeat { deleteSelected() }
        return true
    }

    func handleSettingsShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
              event.charactersIgnoringModifiers == "," || event.keyCode == UInt16(kVK_ANSI_Comma)
        else { return false }
        if !event.isARepeat { toggleFeatureSettings() }
        return true
    }

    private var hasMarkedText: Bool {
        (searchField.currentEditor() as? NSTextView)?.hasMarkedText() == true
    }

    func showFeatureSettings() {
        guard !isShowingSettings else { return }
        if settingsView == nil {
            let settings = ClipboardSettingsView(model: model, onClose: { [weak self] in self?.closeSettings() })
            addSubview(settings)
            settingsView = settings
        }
        isShowingSettings = true
        render()
        needsLayout = true
        layoutSubtreeIfNeeded()
        if let settingsView { window?.makeFirstResponder(settingsView) }
    }

    func closeSettings() {
        guard isShowingSettings else { return }
        isShowingSettings = false
        render()
        needsLayout = true
        layoutSubtreeIfNeeded()
        if window?.isVisible == true { window?.makeFirstResponder(searchField) }
    }

    override func cancelOperation(_ sender: Any?) {
        if isShowingSettings { closeSettings() } else { onBack() }
    }

    private func toggleFeatureSettings() {
        if isShowingSettings { closeSettings() } else { showFeatureSettings() }
    }

    private func render() {
        isUpdating = true
        defer { isUpdating = false }
        let queryChanged = displayedQuery != model.query
        displayedQuery = model.query
        if searchField.stringValue != model.query { searchField.stringValue = model.query }
        let resultsChanged = displayedResults.count != model.results.count ||
            zip(displayedResults, model.results).contains { $0.id != $1.id || $0.copiedAt != $1.copiedAt }
        if resultsChanged {
            displayedResults = model.results
            table.reloadData()
        }
        if let row = displayedResults.firstIndex(where: { $0.id == model.selectedID }) {
            let selectionChanged = table.selectedRow != row
            if selectionChanged { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
            if selectionChanged || resultsChanged || queryChanged { table.scrollRowToVisible(row) }
        } else {
            table.deselectAll(nil)
        }
        let isEmpty = displayedResults.isEmpty
        let showIntroduction = isEmpty && model.query.isEmpty && !model.recordingEnabled && !model.isLoading
        scroll.isHidden = isShowingSettings || isEmpty
        emptyLabel.isHidden = isShowingSettings || !isEmpty
        enableButton.isHidden = isShowingSettings || !showIntroduction
        searchField.isHidden = isShowingSettings
        searchIcon.isHidden = isShowingSettings
        copyButton.isHidden = isShowingSettings
        deleteButton.isHidden = isShowingSettings
        settingsView?.isHidden = !isShowingSettings
        backButton.toolTip = isShowingSettings ? text.backToHistory : text.backHelp
        backButton.setAccessibilityLabel(isShowingSettings ? text.backToHistory : text.back)
        if model.isLoading {
            emptyLabel.stringValue = text.loading
        } else if showIntroduction {
            emptyLabel.stringValue = text.enableDescription
        } else {
            emptyLabel.stringValue = model.query.isEmpty ? text.noHistory : text.noResults
        }
        footer.stringValue = model.errorMessage ?? model.statusMessage ??
            (model.recordingEnabled ? text.recording : text.paused)
        footer.textColor = model.errorMessage == nil ? .secondaryLabelColor : .systemRed
        footer.toolTip = model.errorMessage ?? model.statusMessage
        let hasSelection = model.selectedEntry != nil
        copyButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection
        let currentDeleteTitle = model.query.isEmpty ? deleteTitle : filteredDeleteTitle
        if deleteButton.title != currentDeleteTitle { deleteButton.title = currentDeleteTitle }
        settingsView?.render()
        let height = preferredHeight
        if height != lastPreferredHeight {
            lastPreferredHeight = height
            onPreferredHeightChange?(height)
        }
        needsLayout = true
    }

    func numberOfRows(in tableView: NSTableView) -> Int { displayedResults.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { ClipboardResultRow() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard displayedResults.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("clipboardCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? ClipboardResultCell ?? ClipboardResultCell()
        cell.identifier = identifier
        let entry = displayedResults[row]
        cell.preview.stringValue = entry.preview
        cell.preview.toolTip = entry.preview
        cell.timestamp.stringValue = L10n.format(text.copiedAt, timestampFormatter.string(from: entry.copiedAt))
        cell.number.stringValue = ResultShortcut.label(for: row)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdating else { return }
        model.select(displayedResults.indices.contains(table.selectedRow) ? displayedResults[table.selectedRow].id : nil)
    }

    func controlTextDidChange(_ notification: Notification) { model.setQuery(searchField.stringValue) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        guard !textView.hasMarkedText(), !isShowingSettings else { return false }
        switch command {
        case #selector(NSResponder.moveDown(_:)): model.moveSelection(by: 1)
        case #selector(NSResponder.moveUp(_:)): model.moveSelection(by: -1)
        case #selector(NSResponder.insertNewline(_:)): copySelected()
        case #selector(NSResponder.cancelOperation(_:)): cancelOperation(nil)
        case #selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.deleteForward(_:)):
            if let event = NSApp.currentEvent, event.type == .keyDown {
                return handleDeleteShortcut(event)
            }
            guard searchField.stringValue.isEmpty, model.query.isEmpty else { return false }
            deleteSelected()
        default: return false
        }
        return true
    }

    @objc private func goBack() {
        if isShowingSettings { closeSettings() } else { onBack() }
    }

    @objc private func copySelected() {
        // The model waits for an in-flight search, so immediate Return uses the new query.
        onCopy(nil)
    }

    @objc private func doubleClickResult() {
        guard table.clickedRow >= 0 else { return }
        copySelected()
    }

    @objc private func deleteSelected() {
        model.removeSelected()
        window?.makeFirstResponder(searchField)
    }

    @objc private func enableRecording() {
        model.setRecordingEnabled(true)
        window?.makeFirstResponder(searchField)
    }
    @objc private func openSettings() { toggleFeatureSettings() }
}

@MainActor
private final class ClipboardSettingsView: NSView {
    private let model: ClipboardModel
    private let onClose: () -> Void
    private let text = ClipboardText.shared
    private let heading = NSTextField(labelWithString: "")
    private let recording = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let retentionLabel = NSTextField(labelWithString: "")
    private let retention = NSPopUpButton(frame: .zero, pullsDown: false)
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let retentionChoices: [ClipboardRetention] = [.hour, .day, .week, .month, .forever]

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(model: ClipboardModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        super.init(frame: NSRect(x: 0, y: 0, width: 480, height: 272))
        heading.stringValue = text.settings
        heading.font = .systemFont(ofSize: 14, weight: .semibold)
        recording.title = text.recordHistory
        recording.target = self
        recording.action = #selector(changeRecording)
        retentionLabel.stringValue = text.retainFor
        retention.addItems(withTitles: [text.hour, text.day, text.week, text.month, text.forever])
        retention.target = self
        retention.action = #selector(changeRetention)
        retention.setAccessibilityLabel(text.retainFor)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        for view in [heading, recording, retentionLabel, retention, detail] { addSubview(view) }
        render()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        heading.frame = NSRect(x: 18, y: 16, width: bounds.width - 36, height: 22)
        recording.frame = NSRect(x: 18, y: 51, width: bounds.width - 36, height: 24)
        retentionLabel.frame = NSRect(x: 18, y: 94, width: 142, height: 22)
        retention.frame = NSRect(x: 176, y: 89, width: bounds.width - 194, height: 28)
        detail.frame = NSRect(x: 18, y: 133, width: bounds.width - 36, height: 104)
    }

    func render() {
        recording.state = model.recordingEnabled ? .on : .off
        if let index = retentionChoices.firstIndex(of: model.retention) { retention.selectItem(at: index) }
        detail.stringValue = text.localOnly + "\n" +
            (model.retention == .forever ? text.noExpiry : text.expires) + "\n" + text.capacity
    }

    override func cancelOperation(_ sender: Any?) { onClose() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, event.keyCode == UInt16(kVK_Escape) {
            onClose()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc private func changeRecording() { model.setRecordingEnabled(recording.state == .on) }

    @objc private func changeRetention() {
        guard retentionChoices.indices.contains(retention.indexOfSelectedItem) else { return }
        model.setRetention(retentionChoices[retention.indexOfSelectedItem])
    }
}
