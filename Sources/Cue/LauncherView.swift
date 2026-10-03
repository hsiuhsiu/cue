import AppKit
import Carbon
import CueCore

private final class ResultsTable: NSTableView {
    var menuForRow: ((Int) -> NSMenu?)?
    // Result clicks keep the search field ready for the next keystroke.
    override var acceptsFirstResponder: Bool { false }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuForRow?(row(at: convert(event.locationInWindow, from: nil)))
    }
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
    let aliasButton = NSButton()
    var hasAppActions = false
    var preferredDetailWidth: CGFloat = 86
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
        aliasButton.isBordered = false
        aliasButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
        aliasButton.contentTintColor = .secondaryLabelColor
        aliasButton.isHidden = true
        aliasButton.refusesFirstResponder = true
        addSubview(icon)
        addSubview(title)
        addSubview(detail)
        addSubview(number)
        addSubview(aliasButton)
        textField = title
        imageView = icon
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        icon.frame = NSRect(x: 8, y: (bounds.height - 28) / 2, width: 28, height: 28)
        let detailWidth: CGFloat = detail.stringValue.isEmpty ? 0 : preferredDetailWidth
        let actionWidth: CGFloat = hasAppActions ? 32 : 0
        title.frame = NSRect(x: 46, y: (bounds.height - titleHeight) / 2,
                             width: max(0, bounds.width - 102 - detailWidth - actionWidth), height: titleHeight)
        detail.frame = NSRect(x: bounds.width - detailWidth - 56 - actionWidth, y: (bounds.height - detailHeight) / 2,
                              width: detailWidth, height: detailHeight)
        aliasButton.frame = NSRect(x: bounds.width - 82, y: (bounds.height - 28) / 2, width: 28, height: 28)
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
    private let onWebSearch: () -> Void
    private let onSearchActions: () -> Void
    private let onAppAlias: (IndexedApplication) -> Void
    private let material = LauncherBackdrop()
    private let table = ResultsTable()
    private let scroll = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let rateProvider = NSButton(title: "Rates By Exchange Rate API", target: nil, action: nil)
    private let separator = NSBox()
    private let actionsButton = NSButton(
        title: L10n.string("search.actionsButton", table: "Launcher", value: "Actions ⌘K"),
        target: nil, action: nil
    )
    private var actionsButtonWidth: CGFloat = 100
    private var inputLineHeight: CGFloat = 0
    private var displayedResults: [LauncherResult] = []
    private var displayedQuery = ""
    private var displayedAllowsWebSearch = false
    private var displayedAllowsGPTNetwork = false
    private var isQueryEmpty = true
    private var isUpdating = false
    private var lastPreferredHeight: CGFloat = 56

    override var isFlipped: Bool { true }

    var preferredHeight: CGFloat {
        let statusHeight: CGFloat = status.isHidden && rateProvider.isHidden ? 0 : 26
        guard !isQueryEmpty else { return 56 + statusHeight }
        guard !displayedResults.isEmpty else { return 120 + statusHeight }
        return 64 + CGFloat(displayedResults.count) * 42 + statusHeight
    }

    init(model: LauncherModel, onSubmit: @escaping () -> Void,
         onCancel: @escaping () -> Void, onSettings: @escaping () -> Void,
         onWebSearch: @escaping () -> Void = {},
         onSearchActions: @escaping () -> Void = {},
         onAppAlias: @escaping (IndexedApplication) -> Void = { _ in }) {
        self.model = model
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self.onSettings = onSettings
        self.onWebSearch = onWebSearch
        self.onSearchActions = onSearchActions
        self.onAppAlias = onAppAlias
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
        actionsButton.bezelStyle = .rounded
        actionsButton.controlSize = .small
        actionsButton.font = .systemFont(ofSize: 12)
        actionsButton.target = self
        actionsButton.action = #selector(showActions)
        let actionsDescription = L10n.string("search.actionsAccessibility", table: "Launcher", value: "Actions for this text (Command-K)")
        actionsButton.toolTip = actionsDescription
        actionsButton.setAccessibilityLabel(actionsDescription)
        actionsButtonWidth = max(86, actionsButton.fittingSize.width)
        actionsButton.isHidden = true
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
        table.menuForRow = { [weak self] row in self?.appMenu(for: row) }
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
        rateProvider.isBordered = false
        rateProvider.font = .systemFont(ofSize: 11)
        rateProvider.contentTintColor = .linkColor
        rateProvider.target = self
        rateProvider.action = #selector(openRateProvider)
        rateProvider.isHidden = true
        for view in [searchField, separator, scroll, emptyLabel, status, rateProvider, actionsButton] { addSubview(view) }
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
        if handleAppAliasShortcut(event) { return true }
        if handleSearchActionsShortcut(event) { return true }
        if handleWebSearchShortcut(event) { return true }
        if handleNumberShortcut(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    func handleAppAliasShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
              event.keyCode == UInt16(kVK_ANSI_E),
              (searchField.currentEditor() as? NSTextView)?.hasMarkedText() != true,
              case .application(let application) = model.selectedResult else { return false }
        if !event.isARepeat { onAppAlias(application) }
        return true
    }

    func handleSearchActionsShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
              event.keyCode == UInt16(kVK_ANSI_K),
              (searchField.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return false }
        if !event.isARepeat && !model.isQueryEmpty { onSearchActions() }
        return true
    }

    func handleWebSearchShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
              event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter),
              (searchField.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return false }
        // Never submit provisional IME text or repeat a browser handoff when held.
        if !event.isARepeat && !model.isQueryEmpty { onWebSearch() }
        return true
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
        let actionsWidth = actionsButton.isHidden ? 0 : actionsButtonWidth + 12
        searchField.frame = NSRect(x: 18, y: (56 - inputLineHeight) / 2,
                                  width: max(0, bounds.width - 36 - actionsWidth), height: inputLineHeight)
        actionsButton.frame = NSRect(x: bounds.width - actionsButtonWidth - 16, y: 15,
                                     width: actionsButtonWidth, height: 26)
        separator.frame = NSRect(x: 0, y: 56, width: bounds.width, height: 1)
        let statusHeight: CGFloat = status.isHidden && rateProvider.isHidden ? 0 : 26
        scroll.frame = NSRect(x: 6, y: 60, width: bounds.width - 12,
                              height: max(0, bounds.height - 64 - statusHeight))
        scroll.layoutSubtreeIfNeeded()
        table.tableColumns.first?.width = scroll.contentSize.width
        emptyLabel.frame = NSRect(x: 16, y: 56 + (max(0, bounds.height - 56 - statusHeight) - 24) / 2,
                                  width: bounds.width - 32, height: 24)
        let providerWidth: CGFloat = rateProvider.isHidden ? 0 : 190
        status.frame = NSRect(x: 18, y: bounds.height - 23, width: max(0, bounds.width - 36 - providerWidth), height: 17)
        rateProvider.frame = NSRect(x: bounds.width - 208, y: bounds.height - 25, width: 190, height: 20)
    }

    private func render() {
        isUpdating = true
        defer { isUpdating = false }
        let queryChanged = displayedQuery != model.query
        displayedQuery = model.query
        isQueryEmpty = model.isQueryEmpty
        actionsButton.isHidden = isQueryEmpty
        if searchField.stringValue != model.query { searchField.stringValue = model.query }
        let visibleResults = isQueryEmpty ? [] : model.results
        let resultsChanged = displayedResults != visibleResults
        let availabilityChanged = displayedAllowsWebSearch != model.allowsWebSearch
        let gptAvailabilityChanged = displayedAllowsGPTNetwork != model.allowsGPTNetwork
        displayedAllowsWebSearch = model.allowsWebSearch
        displayedAllowsGPTNetwork = model.allowsGPTNetwork
        if resultsChanged || (availabilityChanged && visibleResults.contains(where: \.isWebSearch))
            || (gptAvailabilityChanged && visibleResults.contains(where: \.isGPTAction)) {
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
        for index in displayedResults.indices {
            guard let cell = table.view(atColumn: 0, row: index, makeIfNecessary: false) as? ResultCell else { continue }
            cell.aliasButton.isHidden = !cell.hasAppActions || index != row
        }
        scroll.isHidden = displayedResults.isEmpty
        emptyLabel.isHidden = isQueryEmpty || !displayedResults.isEmpty
        separator.isHidden = isQueryEmpty
        emptyLabel.stringValue = model.isIndexing ? text.findingApplications : text.noResults
        let error = model.launchError ?? model.shortcutError
        let showsRates = visibleResults.contains { if case .conversion(let result) = $0 { return result.isCurrency }; return false }
        rateProvider.isHidden = !showsRates
        let message = error ?? model.actionStatus ?? (showsRates ? model.currencyRateDate : nil)
            ?? (model.isIndexing ? text.updatingIndex : (isQueryEmpty ? nil : model.indexStatus))
            ?? (model.isShowingSearchActions ? text.searchActions : nil)
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
        cell.title.textColor = .labelColor
        cell.toolTip = nil
        cell.hasAppActions = false
        cell.aliasButton.isHidden = true
        cell.preferredDetailWidth = result.isWebSearch ? 140 : 86
        switch result {
        case .conversion(let conversion):
            cell.title.stringValue = (conversion.isApproximate ? "≈ " : "= ") + conversion.value + " " + conversion.unitSymbol
            cell.detail.stringValue = text.calculationCopy
            cell.preferredDetailWidth = 100
            cell.toolTip = cell.title.stringValue
        case .currencyStatus(let state):
            switch state {
            case .networkRequired: cell.title.stringValue = text.currencyNetworkRequired
            case .loading: cell.title.stringValue = text.currencyLoading
            case .unavailable: cell.title.stringValue = text.currencyUnavailable
            case .unsupported: cell.title.stringValue = text.currencyUnsupported
            }
            cell.title.textColor = .secondaryLabelColor
            cell.detail.stringValue = state == .unavailable ? text.currencyRetry : (state == .networkRequired ? text.currencyDisabled : "")
            cell.preferredDetailWidth = 90
        case .calculation(let calculation):
            cell.title.stringValue = (calculation.isApproximate ? "≈ " : "= ") + calculation.value
            cell.detail.stringValue = text.calculationCopy
            cell.preferredDetailWidth = 100
            cell.toolTip = cell.title.stringValue
        case .application(let application):
            cell.title.stringValue = application.name
            cell.detail.stringValue = application.searchAlias ?? ""
            cell.icon.image = model.icons.image(for: application)
            cell.hasAppActions = true
            cell.aliasButton.isHidden = result.id != model.selectedID
            cell.aliasButton.toolTip = text.appAliasHelp
            cell.aliasButton.setAccessibilityLabel(text.editAppAlias + " " + application.name)
            cell.aliasButton.target = self
            cell.aliasButton.action = #selector(editAppAlias(_:))
            cell.aliasButton.tag = row
        case .googleSearch, .googleSearchIn:
            cell.title.stringValue = text.googleSearch
            let browserName: String
            if case .googleSearchIn(let browser) = result { browserName = browser.name }
            else { browserName = text.defaultBrowser }
            cell.detail.stringValue = model.allowsWebSearch ? browserName : text.webSearchOff
            cell.title.textColor = model.allowsWebSearch ? .labelColor : .secondaryLabelColor
            cell.toolTip = model.allowsWebSearch ? text.browserChoices : text.webSearchDisabled
        case .webSearchSettings:
            cell.title.stringValue = text.webSearchSettings
            cell.detail.stringValue = text.command
        case .chooseSearchBrowser:
            cell.title.stringValue = text.chooseSearchBrowser
            cell.detail.stringValue = "↵"
        case .askGPT, .translateGPT:
            cell.title.stringValue = result == .askGPT ? text.askGPT : text.translateGPT
            cell.detail.stringValue = model.allowsGPTNetwork
                ? (result == .askGPT ? text.gptAnswerDetail : text.gptTranslateDetail) : text.gptNetworkOff
            cell.title.textColor = model.allowsGPTNetwork ? .labelColor : .secondaryLabelColor
            cell.toolTip = text.gptHelp
            cell.preferredDetailWidth = 120
        case .gptSettings:
            cell.title.stringValue = text.gptSettings
            cell.detail.stringValue = text.command
        case .updateIndex:
            cell.title.stringValue = text.updateIndex
            cell.detail.stringValue = text.command
        case .cleanLink:
            cell.title.stringValue = text.cleanLink
            cell.detail.stringValue = text.cleanLinkDetail
        case .emojiSearch:
            cell.title.stringValue = text.emojiSearch
            cell.detail.stringValue = text.command
        case .clipboardHistory:
            cell.title.stringValue = text.clipboardHistory
            cell.detail.stringValue = text.command
        case .sleep:
            cell.title.stringValue = text.sleep
            cell.detail.stringValue = text.command
        case .lockScreen:
            cell.title.stringValue = text.lockScreen
            cell.detail.stringValue = text.command
        case .screenOff:
            cell.title.stringValue = text.screenOff
            cell.detail.stringValue = text.command
        case .convertToTraditional:
            cell.title.stringValue = text.convertToTraditional
            cell.detail.stringValue = text.traditionalRegion
        case .convertToSimplified:
            cell.title.stringValue = text.convertToSimplified
            cell.detail.stringValue = text.simplifiedRegion
        case .chineseConversionSettings:
            cell.title.stringValue = text.chineseConversionSettings
            cell.detail.stringValue = text.command
        }
        if result.isWebSearch { cell.icon.image = model.icons.image(forWebSearch: result) }
        else if let command = CommandIcon(result) { cell.icon.image = model.icons.image(for: command) }
        return cell
    }

    private func appMenu(for row: Int) -> NSMenu? {
        guard displayedResults.indices.contains(row),
              case .application = displayedResults[row],
              (searchField.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return nil }
        model.select(displayedResults[row].id)
        let menu = NSMenu()
        let item = NSMenuItem(title: text.editAppAlias, action: #selector(editAppAlias(_:)), keyEquivalent: "e")
        item.keyEquivalentModifierMask = .command
        item.target = self
        // A background reindex can finish while a native menu is open. Bind
        // the action to the app identity rather than a row that may have moved.
        item.representedObject = displayedResults[row].id
        menu.addItem(item)
        return menu
    }

    @objc private func editAppAlias(_ sender: AnyObject) {
        let row: Int
        if let button = sender as? NSButton { row = button.tag }
        else if let item = sender as? NSMenuItem,
                let id = item.representedObject as? String,
                let index = displayedResults.firstIndex(where: { $0.id == id }) { row = index }
        else { return }
        guard displayedResults.indices.contains(row),
              case .application(let application) = displayedResults[row],
              (searchField.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
        model.select(displayedResults[row].id)
        onAppAlias(application)
    }

    @objc private func openRateProvider() {
        guard !rateProvider.isHidden, let url = URL(string: "https://www.exchangerate-api.com") else { return }
        NSWorkspace.shared.open(url)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdating, displayedResults.indices.contains(table.selectedRow) else { return }
        model.select(displayedResults[table.selectedRow].id)
    }

    private func updateIcon(_ loadedID: String) {
        // Badge callbacks update existing cells; generic artwork also refreshes
        // browser rows still waiting for their first badge or using the fallback.
        for (row, result) in displayedResults.enumerated() {
            let matches: Bool
            if case .application(let app) = result { matches = app.id == loadedID }
            else if result.isWebSearch {
                matches = result.id == loadedID || loadedID == LauncherResult.googleSearch.id
            } else { matches = CommandIcon(result)?.resultID == loadedID }
            guard matches,
                  let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? ResultCell else { continue }
            if case .application(let application) = result {
                cell.icon.image = model.icons.image(for: application)
            } else if result.isWebSearch {
                cell.icon.image = model.icons.image(forWebSearch: result)
            } else if let command = CommandIcon(result) {
                cell.icon.image = model.icons.image(for: command)
            }
        }
    }

    @objc private func clickedResult() {
        guard table.clickedRow >= 0,
              (searchField.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
        onSubmit()
    }

    @objc private func showActions() {
        guard !model.isQueryEmpty,
              (searchField.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
        onSearchActions()
        window?.makeFirstResponder(searchField)
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
