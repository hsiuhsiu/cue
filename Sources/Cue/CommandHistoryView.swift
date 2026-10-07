import AppKit
import Carbon
import CueCore

enum CommandHistoryText {
    static func value(_ key: String, _ fallback: String) -> String {
        L10n.string(key, table: "CommandHistory", value: fallback)
    }
    static let title = value("title", "Command History")
    static let search = value("search", "Search executed inputs…")
    static let empty = value("empty", "Executed inputs appear here. On an empty launcher, press ↑ to recall one.")
    static let noResults = value("noResults", "No matching history.")
    static let loading = value("loading", "Loading history…")
    static let use = value("use", "Use ↩")
    static let delete = value("delete", "Delete ⌘⌫")
    static let settings = value("settings", "History Settings")
    static let recording = value("recording", "Record executed inputs")
    static let privacy = value("privacy", "Includes Google searches, GPT inputs, calculations and filenames. Saved only on this Mac, without responses or clipboard contents.")
    static let capacity = value("capacity", "Up to 200 entries · 30 days")
    static let clear = value("clear", "Clear All History")
    static let confirm = value("confirm", "Confirm Clear All")
    static let error = value("error", "Couldn’t save history. Check free space and folder permissions.")
    static let paused = value("paused", "Recording is off")
    static let back = value("back", "Back (Esc)")
    static let useHelp = value("use.help", "Restore this input and action; press Return again to execute.")
    static let previous = value("previous", "Previous page")
    static let next = value("next", "Next page")
    static let page = value("page", "%ld–%ld of %ld")

    private static let names: [String: String] = {
        let text = LauncherText.shared
        return [
            LauncherResult.updateIndex.id: text.updateIndex,
            LauncherResult.clipboardHistory.id: text.clipboardHistory,
            LauncherResult.sleep.id: text.sleep, LauncherResult.lockScreen.id: text.lockScreen,
            LauncherResult.screenOff.id: text.screenOff,
            LauncherResult.windowControls.id: text.windowControls, LauncherResult.windowSettings.id: text.windowSettings,
            LauncherResult.convertToTraditional.id: text.convertToTraditional,
            LauncherResult.convertToSimplified.id: text.convertToSimplified,
            LauncherResult.chineseConversionSettings.id: text.chineseConversionSettings,
            LauncherResult.googleSearch.id: text.googleSearch,
            LauncherResult.webSearchSettings.id: text.webSearchSettings,
            LauncherResult.askGPT.id: text.askGPT, LauncherResult.translateGPT.id: text.translateGPT,
            LauncherResult.gptSettings.id: text.gptSettings, LauncherResult.cleanLink.id: text.cleanLink,
            LauncherResult.emojiSearch.id: text.emojiSearch,
        ]
    }()
    static func action(_ entry: CommandHistoryEntry) -> String {
        let text = LauncherText.shared
        if entry.actionID.hasPrefix("action:google-search:") { return text.googleSearch + " · " + entry.title }
        return names[entry.actionID] ?? entry.title
    }
}

private final class HistoryTable: NSTableView {
    override var acceptsFirstResponder: Bool { false }
}
private final class HistoryRow: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        LauncherAppearance.selection.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 8, yRadius: 8).fill()
    }
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}
private final class HistoryCell: NSTableCellView {
    let query = NSTextField(labelWithString: "")
    let detail = NSTextField(labelWithString: "")
    let number = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        query.font = .systemFont(ofSize: 18)
        query.lineBreakMode = .byTruncatingTail
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        number.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        number.textColor = .secondaryLabelColor
        number.alignment = .right
        [query, detail, number].forEach(addSubview)
        textField = query
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        query.frame = NSRect(x: 12, y: 21, width: max(0, bounds.width - 70), height: 23)
        detail.frame = NSRect(x: 12, y: 4, width: max(0, bounds.width - 70), height: 16)
        number.frame = NSRect(x: bounds.width - 51, y: 15, width: 40, height: 18)
    }
}

/// Only nine native rows are rendered; keyboard navigation pages through the
/// bounded history without scrollbars. Filtering uses prepared in-memory text.
@MainActor
final class CommandHistoryView: NSView, NSTextFieldDelegate, NSTableViewDelegate, NSTableViewDataSource {
    let searchField = NSTextField()
    var onPreferredHeightChange: ((CGFloat) -> Void)?
    private let model: CommandHistoryModel
    private let onUse: (CommandHistoryEntry) -> Void
    private let onBack: () -> Void
    private let backdrop = LauncherBackdrop()
    private let back = NSButton()
    private let heading = NSTextField(labelWithString: CommandHistoryText.title)
    private let settings = NSButton()
    private let scroll = NSScrollView()
    private let table = HistoryTable()
    private let empty = NSTextField(wrappingLabelWithString: "")
    private let footer = NSTextField(labelWithString: "")
    private let use = NSButton()
    private let delete = NSButton()
    private let previous = NSButton()
    private let next = NSButton()
    private let recording = NSButton(checkboxWithTitle: CommandHistoryText.recording, target: nil, action: nil)
    private let privacy = NSTextField(wrappingLabelWithString: CommandHistoryText.privacy)
    private let clear = NSButton()
    private let date = DateFormatter()
    private var documents: [(entry: CommandHistoryEntry, key: String, detail: String)] = []
    private var matches: [Int] = []
    private var rows: [Int] = []
    private var page = 0
    private var updating = false
    private var active = false
    private var showingSettings = false
    private var confirmingClear = false
    private var lastHeight: CGFloat = 220
    var preferredHeight: CGFloat { showingSettings ? 260 : max(220, 136 + CGFloat(rows.count) * 50) }
    override var isFlipped: Bool { true }

    init(model: CommandHistoryModel, onUse: @escaping (CommandHistoryEntry) -> Void, onBack: @escaping () -> Void) {
        self.model = model; self.onUse = onUse; self.onBack = onBack
        super.init(frame: NSRect(x: 0, y: 0, width: 640, height: 220))
        wantsLayer = true; layer?.cornerRadius = 16; layer?.masksToBounds = true
        addSubview(backdrop)
        date.dateStyle = .short; date.timeStyle = .short
        configure(back, title: "‹ esc", action: #selector(goBack))
        back.toolTip = CommandHistoryText.back
        heading.font = .systemFont(ofSize: 14, weight: .semibold)
        configure(settings, title: "", action: #selector(toggleSettings))
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: CommandHistoryText.settings)
        settings.toolTip = CommandHistoryText.settings
        configure(use, title: CommandHistoryText.use, action: #selector(useSelected))
        use.toolTip = CommandHistoryText.useHelp
        configure(delete, title: CommandHistoryText.delete, action: #selector(deleteSelected))
        configure(previous, title: "‹", action: #selector(previousPage))
        configure(next, title: "›", action: #selector(nextPage))
        previous.setAccessibilityLabel(CommandHistoryText.previous)
        next.setAccessibilityLabel(CommandHistoryText.next)
        configure(clear, title: CommandHistoryText.clear, action: #selector(clearAll))
        recording.target = self; recording.action = #selector(toggleRecording)
        searchField.font = .systemFont(ofSize: 21)
        searchField.placeholderString = CommandHistoryText.search
        searchField.isBordered = false; searchField.drawsBackground = false
        searchField.focusRingType = .none; searchField.usesSingleLineMode = true
        searchField.delegate = self; searchField.setAccessibilityLabel(CommandHistoryText.search)
        empty.alignment = .center; empty.textColor = .secondaryLabelColor
        footer.font = .systemFont(ofSize: 11); footer.textColor = .secondaryLabelColor
        footer.lineBreakMode = .byTruncatingTail
        privacy.font = .systemFont(ofSize: 13); privacy.textColor = .secondaryLabelColor
        table.headerView = nil; table.backgroundColor = .clear; table.style = .plain
        table.rowHeight = 48; table.intercellSpacing = NSSize(width: 0, height: 2)
        table.focusRingType = .none; table.allowsEmptySelection = true
        table.delegate = self; table.dataSource = self
        table.target = self; table.doubleAction = #selector(useSelected)
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("history")))
        table.setAccessibilityLabel(CommandHistoryText.title)
        scroll.documentView = table
        scroll.hasVerticalScroller = false; scroll.hasHorizontalScroller = false
        scroll.verticalScrollElasticity = .none; scroll.horizontalScrollElasticity = .none
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.automaticallyAdjustsContentInsets = false
        [back, heading, settings, searchField, scroll, empty, footer, use, delete, previous, next,
         recording, privacy, clear].forEach(addSubview)
        model.onChange = { [weak self] in
            guard let self, self.active else { return }
            self.prepareDocuments()
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    private func configure(_ button: NSButton, title: String, action: Selector) {
        button.title = title; button.bezelStyle = .rounded
        button.target = self; button.action = action; button.refusesFirstResponder = true
    }

    func open() {
        active = true; showingSettings = false; page = 0
        model.refresh()
        prepareDocuments()
    }
    func close() {
        active = false; confirmingClear = false; showingSettings = false
        searchField.stringValue = ""
        documents.removeAll(); matches.removeAll(); rows.removeAll()
        table.reloadData()
    }
    func focusInput() {
        if showingSettings { window?.makeFirstResponder(recording) }
        else { window?.makeFirstResponder(searchField) }
    }
    private func prepareDocuments() {
        let selected = rows.indices.contains(table.selectedRow) ? documents[rows[table.selectedRow]].entry.id : nil
        documents = model.history.entries.map {
            let title = CommandHistoryText.action($0)
            return ($0, SearchEngine.normalize($0.query + " " + title), title + " · " + date.string(from: $0.date))
        }
        filter(preserving: selected)
    }
    private func filter(preserving selected: UUID? = nil) {
        let input = searchField.stringValue
        let key = input.utf8.count <= 1_024 ? SearchEngine.normalize(input) : nil
        matches = key.map { key in documents.indices.filter { key.isEmpty || documents[$0].key.contains(key) } } ?? []
        page = min(page, max(0, (matches.count - 1) / 9))
        let selectedIndex = selected.flatMap { id in matches.firstIndex { documents[$0].entry.id == id } }
        if let selectedIndex { page = selectedIndex / 9 }
        render(selectedRow: selectedIndex.map { $0 % 9 } ?? 0)
    }
    private func render(selectedRow: Int = 0) {
        updating = true
        defer { updating = false }
        rows = Array(matches.dropFirst(page * 9).prefix(9))
        table.reloadData()
        if !rows.isEmpty { table.selectRowIndexes(IndexSet(integer: min(selectedRow, rows.count - 1)), byExtendingSelection: false) }
        let noRows = rows.isEmpty
        searchField.isHidden = showingSettings
        scroll.isHidden = showingSettings || noRows
        empty.isHidden = showingSettings || !noRows
        empty.stringValue = model.isLoading ? CommandHistoryText.loading
            : (searchField.stringValue.isEmpty ? CommandHistoryText.empty : CommandHistoryText.noResults)
        [use, delete, previous, next].forEach { $0.isHidden = showingSettings }
        [recording, privacy, clear].forEach { $0.isHidden = !showingSettings }
        use.isEnabled = !noRows; delete.isEnabled = !noRows
        previous.isEnabled = page > 0; next.isEnabled = (page + 1) * 9 < matches.count
        recording.state = model.isEnabled ? .on : .off
        clear.isEnabled = !model.history.entries.isEmpty
        clear.title = confirmingClear ? CommandHistoryText.confirm : CommandHistoryText.clear
        heading.stringValue = showingSettings ? CommandHistoryText.settings : CommandHistoryText.title
        footer.stringValue = model.saveFailed ? CommandHistoryText.error
            : !model.isEnabled ? CommandHistoryText.paused
            : showingSettings || noRows ? CommandHistoryText.capacity
            : L10n.format(CommandHistoryText.page, page * 9 + 1, page * 9 + rows.count, matches.count)
        footer.toolTip = footer.stringValue
        if preferredHeight != lastHeight { lastHeight = preferredHeight; onPreferredHeightChange?(lastHeight) }
        needsLayout = true
    }
    override func layout() {
        super.layout()
        backdrop.frame = bounds
        back.frame = NSRect(x: 10, y: 10, width: 62, height: 26)
        heading.frame = NSRect(x: 82, y: 15, width: bounds.width - 136, height: 20)
        settings.frame = NSRect(x: bounds.width - 46, y: 10, width: 32, height: 26)
        searchField.frame = NSRect(x: 18, y: 49, width: bounds.width - 36, height: 30)
        scroll.frame = NSRect(x: 6, y: 86, width: bounds.width - 12, height: CGFloat(rows.count) * 50)
        table.tableColumns.first?.width = scroll.contentSize.width
        empty.frame = NSRect(x: 30, y: 100, width: bounds.width - 60, height: 60)
        footer.frame = NSRect(x: 18, y: bounds.height - 33, width: bounds.width - 330, height: 18)
        previous.frame = NSRect(x: bounds.width - 298, y: bounds.height - 39, width: 30, height: 28)
        next.frame = NSRect(x: bounds.width - 264, y: bounds.height - 39, width: 30, height: 28)
        delete.frame = NSRect(x: bounds.width - 224, y: bounds.height - 39, width: 120, height: 28)
        use.frame = NSRect(x: bounds.width - 100, y: bounds.height - 39, width: 84, height: 28)
        recording.frame = NSRect(x: 24, y: 58, width: bounds.width - 48, height: 28)
        privacy.frame = NSRect(x: 24, y: 99, width: bounds.width - 48, height: 62)
        clear.frame = NSRect(x: 24, y: 177, width: 210, height: 30)
        if showingSettings { footer.frame.size.width = bounds.width - 36 }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { HistoryRow() }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row) else { return nil }
        let id = NSUserInterfaceItemIdentifier("history-cell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? HistoryCell) ?? HistoryCell()
        cell.identifier = id
        let item = documents[rows[row]]
        cell.query.stringValue = item.entry.query.replacingOccurrences(of: "\n", with: " ")
        cell.query.toolTip = item.entry.query
        cell.detail.stringValue = item.detail; cell.number.stringValue = "⌘\(row + 1)"
        return cell
    }
    func controlTextDidChange(_ obj: Notification) { page = 0; filter() }
    private var hasMarkedText: Bool { (searchField.currentEditor() as? NSTextView)?.hasMarkedText() == true }
    @objc private func useSelected() {
        guard !showingSettings, !hasMarkedText, rows.indices.contains(table.selectedRow) else { return }
        onUse(documents[rows[table.selectedRow]].entry)
    }
    @objc private func deleteSelected() {
        guard !showingSettings, !hasMarkedText, rows.indices.contains(table.selectedRow) else { return }
        model.remove(documents[rows[table.selectedRow]].entry.id)
    }
    @objc private func toggleRecording() { model.setEnabled(recording.state == .on) }
    @objc private func clearAll() {
        if confirmingClear { model.clear(); confirmingClear = false }
        else { confirmingClear = true }
        render()
    }
    @objc private func previousPage() { if page > 0 { page -= 1; render() } }
    @objc private func nextPage() { if (page + 1) * 9 < matches.count { page += 1; render() } }
    @objc private func toggleSettings() { showingSettings.toggle(); confirmingClear = false; render(); focusInput() }
    @objc private func goBack() { if showingSettings { toggleSettings() } else { onBack() } }
    override func cancelOperation(_ sender: Any?) { if !hasMarkedText { goBack() } }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleKeyEquivalent(event) || super.performKeyEquivalent(with: event)
    }
    func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, !hasMarkedText else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == .command, event.keyCode == UInt16(kVK_ANSI_Comma) {
            if !event.isARepeat { toggleSettings() }; return true
        }
        guard !showingSettings else { return false }
        if let row = ResultShortcut.index(for: event) {
            if !event.isARepeat, rows.indices.contains(row) { onUse(documents[rows[row]].entry) }
            return true
        }
        if modifiers == .command, event.keyCode == UInt16(kVK_Delete) {
            if !event.isARepeat { deleteSelected() }; return true
        }
        return false
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        guard !textView.hasMarkedText(), !showingSettings else { return false }
        switch command {
        case #selector(NSResponder.moveDown(_:)):
            if table.selectedRow + 1 < rows.count {
                table.selectRowIndexes(IndexSet(integer: table.selectedRow + 1), byExtendingSelection: false)
            } else { nextPage() }
        case #selector(NSResponder.moveUp(_:)):
            if table.selectedRow > 0 { table.selectRowIndexes(IndexSet(integer: table.selectedRow - 1), byExtendingSelection: false) }
            else if page > 0 { page -= 1; render(selectedRow: 8) }
        case #selector(NSResponder.insertNewline(_:)): useSelected()
        case #selector(NSResponder.cancelOperation(_:)): goBack()
        case #selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.deleteForward(_:)):
            guard searchField.stringValue.isEmpty else { return false }
            deleteSelected()
        default: return false
        }
        return true
    }
}
