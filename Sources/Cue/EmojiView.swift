import AppKit
import Carbon
import CueCore

struct EmojiText {
    static let shared = EmojiText()
    let title = L10n.string("title", table: "Emoji", value: "Emoji")
    let back = L10n.string("back", table: "Emoji", value: "Back to launcher (Esc)")
    let search = L10n.string("search", table: "Emoji", value: "Search emoji…")
    let results = L10n.string("results", table: "Emoji", value: "Emoji results")
    let loading = L10n.string("loading", table: "Emoji", value: "Loading emoji…")
    let noResults = L10n.string("empty", table: "Emoji", value: "No matching emoji. Try another word.")
    let copy = L10n.string("copy", table: "Emoji", value: "Copy")
    let copyHelp = L10n.string("copy.help", table: "Emoji", value: "Copy selected emoji (Return)")
    let copying = L10n.string("copying", table: "Emoji", value: "Copying…")
    let retry = L10n.string("retry", table: "Emoji", value: "Retry")
    let loadError = L10n.string("error.load", table: "Emoji", value: "Couldn’t load emoji. Please try again.")
    let copyError = L10n.string("error.copy", table: "Emoji", value: "Couldn’t copy this emoji. Please try again.")
    let accessError = L10n.string("error.access", table: "Emoji", value: "Clipboard access is blocked. Allow Cue in System Settings, then try again.")
    let usesTraditionalNames = L10n.string("names.language", table: "Emoji", value: "en") == "zh-Hant"

    func name(for entry: EmojiEntry) -> String {
        usesTraditionalNames && !entry.traditionalName.isEmpty ? entry.traditionalName : entry.name
    }
}

private final class EmojiResultsTable: NSTableView {
    override var acceptsFirstResponder: Bool { false }
}

private final class EmojiResultRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        LauncherAppearance.selection.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 8, yRadius: 8).fill()
    }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

private final class EmojiResultCell: NSTableCellView {
    let glyph = NSImageView()
    let name = NSTextField(labelWithString: "")
    let number = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        glyph.imageScaling = .scaleProportionallyUpOrDown
        name.font = .systemFont(ofSize: 16)
        name.lineBreakMode = .byTruncatingTail
        number.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        number.textColor = .secondaryLabelColor
        number.alignment = .right
        for view in [glyph, name, number] { addSubview(view) }
        textField = name
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        glyph.frame = NSRect(x: 15, y: 7, width: 28, height: 28)
        name.frame = NSRect(x: 60, y: 10, width: max(0, bounds.width - 128), height: 23)
        number.frame = NSRect(x: bounds.width - 57, y: 13, width: 47, height: 18)
    }
}

/// This feature owns its small native view; search never rebuilds a SwiftUI tree.
@MainActor
final class EmojiView: NSView, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let searchField = NSTextField()
    private let model: EmojiModel
    private let onCopy: (Int?) -> Void
    private let onBack: () -> Void
    var onSettings: (() -> Void)?
    private let text = EmojiText.shared
    private let material = LauncherBackdrop()
    private let backButton = NSButton()
    private let heading = NSTextField(labelWithString: "")
    private let separator = NSBox()
    private let table = EmojiResultsTable()
    private let scroll = NSScrollView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let retryButton = NSButton()
    private let footerSeparator = NSBox()
    private let footer = NSTextField(labelWithString: "")
    private let copyButton = NSButton()
    private var displayedResults: [EmojiEntry] = []
    private var displayedQuery = ""
    private var isUpdating = false
    private var lastPreferredHeight: CGFloat = 220
    var onPreferredHeightChange: ((CGFloat) -> Void)?
    var preferredHeight: CGFloat { displayedResults.isEmpty ? 220 : 124 + CGFloat(displayedResults.count) * 44 }
    override var isFlipped: Bool { true }

    init(model: EmojiModel, onCopy: @escaping (Int?) -> Void, onBack: @escaping () -> Void,
         onSettings: @escaping () -> Void = {}) {
        self.model = model
        self.onCopy = onCopy
        self.onBack = onBack
        self.onSettings = onSettings
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
        backButton.toolTip = text.back
        backButton.setAccessibilityLabel(text.back)
        heading.stringValue = text.title
        heading.font = .systemFont(ofSize: 14, weight: .semibold)
        searchField.placeholderString = text.search
        searchField.font = .systemFont(ofSize: 21)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.usesSingleLineMode = true
        searchField.delegate = self
        searchField.setAccessibilityLabel(text.search)
        separator.boxType = .separator
        footerSeparator.boxType = .separator
        table.headerView = nil
        table.style = .plain
        table.autoresizingMask = [.width]
        table.backgroundColor = .clear
        table.rowHeight = 42
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.focusRingType = .none
        table.allowsEmptySelection = true
        table.delegate = self
        table.dataSource = self
        table.target = self
        table.doubleAction = #selector(copySelected)
        table.setAccessibilityLabel(text.results)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("emoji"))
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
        retryButton.title = text.retry
        retryButton.bezelStyle = .rounded
        retryButton.target = self
        retryButton.action = #selector(retry)
        footer.font = .systemFont(ofSize: 11)
        footer.lineBreakMode = .byTruncatingTail
        copyButton.title = text.copy + "  ↵"
        copyButton.bezelStyle = .rounded
        copyButton.target = self
        copyButton.action = #selector(copySelected)
        copyButton.toolTip = text.copyHelp
        copyButton.setAccessibilityLabel(text.copyHelp)
        for view in [backButton, heading, searchField, separator, scroll, emptyLabel,
                     retryButton, footerSeparator, footer, copyButton] { addSubview(view) }
        model.onChange = { [weak self] in self?.render() }
        model.glyphs.onLoad = { [weak self] in self?.updateGlyphs() }
        render()
        layoutSubtreeIfNeeded()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        material.frame = bounds
        backButton.frame = NSRect(x: 10, y: 5, width: 58, height: 26)
        heading.frame = NSRect(x: 80, y: 9, width: max(0, bounds.width - 94), height: 21)
        searchField.frame = NSRect(x: 14, y: 39, width: max(0, bounds.width - 28), height: 32)
        separator.frame = NSRect(x: 0, y: 78, width: bounds.width, height: 1)
        scroll.frame = NSRect(x: 6, y: 84, width: max(0, bounds.width - 12), height: max(0, bounds.height - 124))
        scroll.layoutSubtreeIfNeeded()
        table.tableColumns.first?.width = scroll.contentSize.width
        let bodyMidY = 84 + max(0, bounds.height - 124) / 2
        emptyLabel.frame = NSRect(x: 20, y: bodyMidY - (retryButton.isHidden ? 18 : 38), width: max(0, bounds.width - 40), height: 36)
        retryButton.frame = NSRect(x: bounds.midX - 45, y: bodyMidY + 2, width: 90, height: 28)
        footerSeparator.frame = NSRect(x: 0, y: bounds.height - 34, width: bounds.width, height: 1)
        footer.frame = NSRect(x: 12, y: bounds.height - 25, width: max(0, bounds.width - 125), height: 18)
        copyButton.frame = NSRect(x: bounds.width - 104, y: bounds.height - 30, width: 94, height: 26)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleSettingsShortcut(event) || handleNumberShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
    func handleNumberShortcut(_ event: NSEvent) -> Bool {
        guard let index = ResultShortcut.index(for: event), !hasMarkedText else { return false }
        if !event.isARepeat && displayedResults.indices.contains(index) { onCopy(index) }
        return true
    }
    func handleSettingsShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
              event.charactersIgnoringModifiers == "," || event.keyCode == UInt16(kVK_ANSI_Comma) else { return false }
        if !event.isARepeat {
            model.cancelPendingCopy()
            onSettings?()
        }
        return true
    }
    private var hasMarkedText: Bool { (searchField.currentEditor() as? NSTextView)?.hasMarkedText() == true }
    override func cancelOperation(_ sender: Any?) { if !hasMarkedText { onBack() } }

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
        } else {
            // A hidden page can finish warming glyphs without publishing a UI
            // callback. Reopening identical results must still adopt those images.
            updateGlyphs()
        }
        if let index = displayedResults.firstIndex(where: { $0.id == model.selectedID }) {
            let selectionChanged = table.selectedRow != index
            if selectionChanged { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
            if selectionChanged || resultsChanged || queryChanged { table.scrollRowToVisible(index) }
        } else { table.deselectAll(nil) }
        let isEmpty = displayedResults.isEmpty
        scroll.isHidden = isEmpty
        emptyLabel.isHidden = !isEmpty
        retryButton.isHidden = !isEmpty || model.isLoading || model.errorMessage != text.loadError
        emptyLabel.stringValue = model.isLoading ? text.loading : (model.errorMessage ?? text.noResults)
        updateFooter()
        copyButton.isEnabled = model.selectedEntry != nil && !model.isLoading && !model.isCopying
        let height = preferredHeight
        if height != lastPreferredHeight {
            lastPreferredHeight = height
            onPreferredHeightChange?(height)
        }
        needsLayout = true
    }

    func numberOfRows(in tableView: NSTableView) -> Int { displayedResults.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { EmojiResultRow() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard displayedResults.indices.contains(row) else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("emojiCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? EmojiResultCell ?? EmojiResultCell()
        cell.identifier = identifier
        let entry = displayedResults[row]
        cell.glyph.image = model.glyphs.image(for: entry)
        cell.name.stringValue = text.name(for: entry)
        cell.number.stringValue = ResultShortcut.label(for: row)
        cell.toolTip = cell.name.stringValue
        cell.setAccessibilityLabel(entry.emoji + " " + cell.name.stringValue)
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdating else { return }
        model.select(displayedResults.indices.contains(table.selectedRow) ? displayedResults[table.selectedRow].id : nil)
    }
    private func updateGlyphs() {
        // A completion may belong to an older query. Match the current entry
        // before updating only its existing native cell; never reload or reshape rows.
        for (row, entry) in displayedResults.enumerated() {
            guard let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? EmojiResultCell else { continue }
            let image = model.glyphs.image(for: entry)
            if cell.glyph.image !== image { cell.glyph.image = image }
        }
        updateFooter()
    }
    private func updateFooter() {
        footer.stringValue = model.isCopying ? text.copying
            : displayedResults.isEmpty ? ""
            : model.errorMessage ?? (model.glyphs.isLoading ? text.loading : "")
        footer.textColor = model.errorMessage == nil ? .secondaryLabelColor : .systemRed
        footer.toolTip = model.errorMessage
    }
    func controlTextDidChange(_ notification: Notification) { model.setQuery(searchField.stringValue) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }
        switch command {
        case #selector(NSResponder.moveDown(_:)): model.moveSelection(by: 1)
        case #selector(NSResponder.moveUp(_:)): model.moveSelection(by: -1)
        case #selector(NSResponder.insertNewline(_:)): copySelected()
        case #selector(NSResponder.cancelOperation(_:)): onBack()
        default: return false
        }
        return true
    }
    @objc private func goBack() { onBack() }
    @objc private func copySelected() { if !hasMarkedText { onCopy(nil) } }
    @objc private func retry() { model.prepare() }
}
