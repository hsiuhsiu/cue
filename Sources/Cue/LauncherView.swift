import AppKit
import Carbon
import CueCore

private final class ResultsTable: NSTableView {
    // Result clicks keep the search field ready for the next keystroke.
    override var acceptsFirstResponder: Bool { false }
}

private final class ResultRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.2).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 8, yRadius: 8).fill()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

private final class ResultCell: NSTableCellView {
    let title = NSTextField(labelWithString: "")
    let detail = NSTextField(labelWithString: "")
    let icon = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        title.font = .systemFont(ofSize: 16)
        title.lineBreakMode = .byTruncatingTail
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        icon.imageScaling = .scaleProportionallyDown
        addSubview(icon)
        addSubview(title)
        addSubview(detail)
        textField = title
        imageView = icon
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 10, y: 8, width: 32, height: 32)
        let detailWidth: CGFloat = detail.stringValue.isEmpty ? 0 : 150
        title.frame = NSRect(x: 54, y: 14, width: max(0, bounds.width - 70 - detailWidth), height: 22)
        detail.frame = NSRect(x: bounds.width - detailWidth - 12, y: 16, width: detailWidth, height: 16)
    }
}

/// Keep keyboard input, selection and visible-row updates on AppKit's direct event path.
@MainActor
final class LauncherView: NSView, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let searchField = NSTextField()
    private let model: LauncherModel
    private let text = LauncherText.shared
    private let onSubmit: () -> Void
    private let onCancel: () -> Void
    private let onSettings: () -> Void
    private let material = NSVisualEffectView()
    private let searchIcon = NSImageView()
    private let escapeHint = NSTextField(labelWithString: "esc")
    private let table = ResultsTable()
    private let scroll = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let footer = NSTextField(labelWithString: "Cue")
    private let keyHint = NSTextField(labelWithString: LauncherText.shared.selectOpen)
    private let settingsButton = NSButton()
    private let separator = NSBox()
    private let footerSeparator = NSBox()
    private var displayedResults: [LauncherResult] = []
    private var displayedQuery = ""
    private var isUpdating = false

    override var isFlipped: Bool { true }

    init(model: LauncherModel, onSubmit: @escaping () -> Void,
         onCancel: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.model = model
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self.onSettings = onSettings
        super.init(frame: NSRect(x: 0, y: 0, width: 680, height: 420))
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        addSubview(material)
        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        searchIcon.contentTintColor = .secondaryLabelColor
        searchField.placeholderString = text.searchPlaceholder
        searchField.font = .systemFont(ofSize: 24)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.usesSingleLineMode = true
        searchField.delegate = self
        searchField.setAccessibilityLabel(text.searchAccessibility)
        escapeHint.font = .systemFont(ofSize: 11)
        escapeHint.textColor = .tertiaryLabelColor
        separator.boxType = .separator
        footerSeparator.boxType = .separator
        table.headerView = nil
        table.backgroundColor = .clear
        table.rowHeight = 48
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.selectionHighlightStyle = .regular
        table.focusRingType = .none
        table.allowsEmptySelection = true
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.action = #selector(clickedResult)
        table.setAccessibilityLabel(text.resultsAccessibility)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        footer.font = .systemFont(ofSize: 11)
        footer.lineBreakMode = .byTruncatingTail
        keyHint.font = .systemFont(ofSize: 11)
        keyHint.textColor = .secondaryLabelColor
        keyHint.alignment = .right
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: text.settings)
        settingsButton.isBordered = false
        settingsButton.target = self
        settingsButton.action = #selector(openSettings)
        settingsButton.toolTip = text.settingsTooltip
        settingsButton.setAccessibilityLabel(text.settings)
        for view in [searchIcon, searchField, escapeHint, separator, scroll, emptyLabel,
                     footerSeparator, footer, keyHint, settingsButton] { addSubview(view) }
        model.onChange = { [weak self] in self?.render() }
        model.icons.onLoad = { [weak self] id in self?.updateIcon(id) }
        render()
        // Construct and lay out once, before any hotkey event is received.
        layoutSubtreeIfNeeded()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Command keys take this path before window.sendEvent, including when Cue is inactive.
        if handleSettingsShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    func handleSettingsShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
              event.charactersIgnoringModifiers == "," || event.keyCode == UInt16(kVK_ANSI_Comma)
        else { return false }
        // Invoke directly, without a button's simulated-click animation or a deferred callback.
        if !event.isARepeat { onSettings() }
        return true
    }

    override func layout() {
        super.layout()
        material.frame = bounds
        searchIcon.frame = NSRect(x: 22, y: 25, width: 25, height: 25)
        searchField.frame = NSRect(x: 60, y: 20, width: max(0, bounds.width - 114), height: 36)
        escapeHint.frame = NSRect(x: bounds.width - 42, y: 31, width: 25, height: 16)
        separator.frame = NSRect(x: 0, y: 75, width: bounds.width, height: 1)
        scroll.frame = NSRect(x: 10, y: 84, width: bounds.width - 20, height: max(0, bounds.height - 129))
        table.tableColumns.first?.width = scroll.contentSize.width
        emptyLabel.frame = NSRect(x: 20, y: bounds.midY, width: bounds.width - 40, height: 24)
        footerSeparator.frame = NSRect(x: 0, y: bounds.height - 36, width: bounds.width, height: 1)
        footer.frame = NSRect(x: 18, y: bounds.height - 26, width: bounds.width - 210, height: 17)
        keyHint.frame = NSRect(x: bounds.width - 180, y: bounds.height - 26, width: 138, height: 17)
        settingsButton.frame = NSRect(x: bounds.width - 32, y: bounds.height - 29, width: 22, height: 22)
    }

    private func render() {
        isUpdating = true
        defer { isUpdating = false }
        let queryChanged = displayedQuery != model.query
        displayedQuery = model.query
        if searchField.stringValue != model.query { searchField.stringValue = model.query }
        let resultsChanged = displayedResults != model.results
        if resultsChanged {
            displayedResults = model.results
            table.reloadData()
        }
        let row = displayedResults.firstIndex { $0.id == model.selectedID }
        if let row {
            let selectionChanged = row != table.selectedRow
            if selectionChanged { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
            if selectionChanged || resultsChanged || queryChanged { table.scrollRowToVisible(row) }
        } else if row == nil {
            table.deselectAll(nil)
        }
        scroll.isHidden = displayedResults.isEmpty
        emptyLabel.isHidden = !displayedResults.isEmpty
        emptyLabel.stringValue = model.isIndexing ? text.findingApplications : text.noResults
        let error = model.launchError ?? model.shortcutError
        footer.stringValue = error ?? (model.isIndexing ? text.updatingIndex : model.indexStatus ?? "Cue")
        footer.textColor = error == nil ? .secondaryLabelColor : .systemRed
        footer.toolTip = error
        keyHint.stringValue = model.selectedResult == .updateIndex ? text.selectRun : text.selectOpen
    }

    func scrollToSelection() {
        if table.selectedRow >= 0 { table.scrollRowToVisible(table.selectedRow) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { displayedResults.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ResultRow()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard displayedResults.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("resultCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? ResultCell ?? ResultCell()
        cell.identifier = identifier
        let result = displayedResults[row]
        cell.title.stringValue = result == .updateIndex ? text.updateIndex : result.name
        cell.detail.stringValue = result == .updateIndex ? text.command : ""
        switch result {
        case .application(let application): cell.icon.image = model.icons.image(for: application)
        case .updateIndex:
            cell.icon.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdating, displayedResults.indices.contains(table.selectedRow) else { return }
        model.select(displayedResults[table.selectedRow].id)
    }

    private func updateIcon(_ applicationID: String) {
        guard let row = displayedResults.firstIndex(where: {
            if case .application(let app) = $0 { return app.id == applicationID }
            return false
        }), case .application(let application) = displayedResults[row],
              let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? ResultCell else { return }
        cell.icon.image = model.icons.image(for: application)
    }

    @objc private func clickedResult() {
        guard table.clickedRow >= 0 else { return }
        onSubmit()
    }

    @objc private func openSettings() { onSettings() }

    func controlTextDidChange(_ notification: Notification) {
        model.setQuery(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        switch command {
        case #selector(NSResponder.moveDown(_:)):
            model.moveSelection(by: 1)
            scrollToSelection()
        case #selector(NSResponder.moveUp(_:)):
            model.moveSelection(by: -1)
            scrollToSelection()
        case #selector(NSResponder.insertNewline(_:)): onSubmit()
        case #selector(NSResponder.cancelOperation(_:)): onCancel()
        default: return false
        }
        return true
    }
}
