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
        LauncherAppearance.selection.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 8, yRadius: 8).fill()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

private final class ResultCell: NSTableCellView {
    let title = NSTextField(labelWithString: "")
    let detail = NSTextField(labelWithString: "")
    let number = NSTextField(labelWithString: "")
    let icon = NSImageView()
    private var titleHeight: CGFloat = 0
    private var detailHeight: CGFloat = 0
    private var numberHeight: CGFloat = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        let titleFont = NSFont.systemFont(ofSize: 20)
        title.font = titleFont
        title.lineBreakMode = .byTruncatingTail
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .right
        number.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        number.textColor = .secondaryLabelColor
        number.alignment = .right
        // Empty labels can round down by a point; reserve the full font height
        // before reused cells receive English or Chinese application names.
        titleHeight = ceil(titleFont.ascender - titleFont.descender + titleFont.leading)
        detailHeight = ceil(detail.intrinsicContentSize.height)
        numberHeight = ceil(number.intrinsicContentSize.height)
        icon.imageScaling = .scaleProportionallyDown
        addSubview(icon)
        addSubview(title)
        addSubview(detail)
        addSubview(number)
        textField = title
        imageView = icon
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 8, y: (bounds.height - 28) / 2, width: 28, height: 28)
        let detailWidth: CGFloat = detail.stringValue.isEmpty ? 0 : 86
        title.frame = NSRect(x: 46, y: (bounds.height - titleHeight) / 2,
                             width: max(0, bounds.width - 102 - detailWidth), height: titleHeight)
        detail.frame = NSRect(x: bounds.width - detailWidth - 56, y: (bounds.height - detailHeight) / 2,
                              width: detailWidth, height: detailHeight)
        number.frame = NSRect(x: bounds.width - 48, y: (bounds.height - numberHeight) / 2,
                              width: 38, height: numberHeight)
    }
}

/// Keep keyboard input, selection and visible-row updates on AppKit's direct event path.
@MainActor
final class LauncherView: NSView, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let searchField = NSTextField()
    var onPreferredHeightChange: ((CGFloat) -> Void)?
    private let model: LauncherModel
    private let text = LauncherText.shared
    private let onSubmit: () -> Void
    private let onCancel: () -> Void
    private let onSettings: () -> Void
    private let material = LauncherBackdrop()
    private let table = ResultsTable()
    private let scroll = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let separator = NSBox()
    private var inputLineHeight: CGFloat = 0
    private var displayedResults: [LauncherResult] = []
    private var displayedQuery = ""
    private var isQueryEmpty = true
    private var isUpdating = false
    private var lastPreferredHeight: CGFloat = 56

    override var isFlipped: Bool { true }

    var preferredHeight: CGFloat {
        let statusHeight: CGFloat = status.isHidden ? 0 : 26
        guard !isQueryEmpty else { return 56 + statusHeight }
        guard !displayedResults.isEmpty else { return 120 + statusHeight }
        return 64 + CGFloat(displayedResults.count) * 42 + statusHeight
    }

    init(model: LauncherModel, onSubmit: @escaping () -> Void,
         onCancel: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.model = model
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self.onSettings = onSettings
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 56))
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        addSubview(material)
        searchField.font = .systemFont(ofSize: 30)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.usesSingleLineMode = true
        searchField.delegate = self
        searchField.setAccessibilityLabel(text.searchAccessibility)
        // Center the native editor's line, not a taller field with unused space
        // below its caret. Resolve this once, outside the typing/layout path.
        inputLineHeight = ceil(searchField.intrinsicContentSize.height)
        separator.boxType = .separator
        table.headerView = nil
        table.style = .plain
        table.autoresizingMask = [.width]
        table.backgroundColor = .clear
        table.rowHeight = 40
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
        status.font = .systemFont(ofSize: 11)
        status.lineBreakMode = .byTruncatingTail
        status.isHidden = true
        for view in [searchField, separator, scroll, emptyLabel, status] { addSubview(view) }
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
        if handleNumberShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    func handleNumberShortcut(_ event: NSEvent) -> Bool {
        guard let row = ResultShortcut.index(for: event),
              (searchField.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return false }
        // A held number never executes again, and absent numbered rows are a no-op.
        guard !event.isARepeat, displayedResults.indices.contains(row) else { return true }
        model.select(displayedResults[row].id)
        onSubmit()
        return true
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
        searchField.frame = NSRect(x: 18, y: (56 - inputLineHeight) / 2,
                                  width: max(0, bounds.width - 36), height: inputLineHeight)
        separator.frame = NSRect(x: 0, y: 56, width: bounds.width, height: 1)
        let statusHeight: CGFloat = status.isHidden ? 0 : 26
        scroll.frame = NSRect(x: 6, y: 60, width: bounds.width - 12,
                              height: max(0, bounds.height - 64 - statusHeight))
        scroll.layoutSubtreeIfNeeded()
        table.tableColumns.first?.width = scroll.contentSize.width
        emptyLabel.frame = NSRect(x: 16, y: 56 + (max(0, bounds.height - 56 - statusHeight) - 24) / 2,
                                  width: bounds.width - 32, height: 24)
        status.frame = NSRect(x: 18, y: bounds.height - 23, width: max(0, bounds.width - 36), height: 17)
    }

    private func render() {
        isUpdating = true
        defer { isUpdating = false }
        let queryChanged = displayedQuery != model.query
        displayedQuery = model.query
        isQueryEmpty = model.query.allSatisfy(\.isWhitespace)
        if searchField.stringValue != model.query { searchField.stringValue = model.query }
        let visibleResults = isQueryEmpty ? [] : model.results
        let resultsChanged = displayedResults != visibleResults
        if resultsChanged {
            displayedResults = visibleResults
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
        emptyLabel.isHidden = isQueryEmpty || !displayedResults.isEmpty
        separator.isHidden = isQueryEmpty
        emptyLabel.stringValue = model.isIndexing ? text.findingApplications : text.noResults
        let error = model.launchError ?? model.shortcutError
        let message = error ?? (model.isIndexing ? text.updatingIndex : (isQueryEmpty ? nil : model.indexStatus))
        status.stringValue = message ?? ""
        status.isHidden = message == nil
        status.textColor = error == nil ? .secondaryLabelColor : .systemRed
        status.toolTip = error
        let height = preferredHeight
        if height != lastPreferredHeight {
            lastPreferredHeight = height
            onPreferredHeightChange?(height)
        }
        needsLayout = true
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
        cell.number.stringValue = ResultShortcut.label(for: row)
        switch result {
        case .application(let application):
            cell.title.stringValue = application.name
            cell.detail.stringValue = ""
            cell.icon.image = model.icons.image(for: application)
        case .updateIndex:
            cell.title.stringValue = text.updateIndex
            cell.detail.stringValue = text.command
            cell.icon.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        case .clipboardHistory:
            cell.title.stringValue = text.clipboardHistory
            cell.detail.stringValue = text.command
            cell.icon.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: nil)
        case .sleep:
            cell.title.stringValue = text.sleep
            cell.detail.stringValue = text.command
            cell.icon.image = NSImage(systemSymbolName: "moon.zzz", accessibilityDescription: nil)
        case .lockScreen:
            cell.title.stringValue = text.lockScreen
            cell.detail.stringValue = text.command
            cell.icon.image = NSImage(systemSymbolName: "lock", accessibilityDescription: nil)
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
