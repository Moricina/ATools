import Foundation
import AppKit

public protocol SearchResultsTableDelegate: AnyObject {
    func searchResultsTable(_ table: SearchResultsTableView, didSelectResult result: SearchResult, isCommandPressed: Bool)
    func searchResultsTable(_ table: SearchResultsTableView, didCompleteDragResult result: SearchResult)
    func searchResultsTableDidRequestDismiss(_ table: SearchResultsTableView)
}

public final class SearchResultCellView: NSTableCellView {
    override public var mouseDownCanMoveWindow: Bool { false }

    public let iconView = NSImageView()
    public let titleLabel = NSTextField(labelWithString: "")
    public let subtitleLabel = NSTextField(labelWithString: "")
    public let badgeContainer = NSView()
    public let badgeLabel = NSTextField(labelWithString: "")
    private var representedIconPath: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 6
        iconView.layer?.masksToBounds = true
        addSubview(iconView)

        badgeContainer.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.wantsLayer = true
        badgeContainer.layer?.cornerRadius = 4
        addSubview(badgeContainer)

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        badgeLabel.alignment = .center
        badgeContainer.addSubview(badgeLabel)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13.5, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            badgeContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            badgeContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            badgeContainer.heightAnchor.constraint(equalToConstant: 18),

            badgeLabel.leadingAnchor.constraint(equalTo: badgeContainer.leadingAnchor, constant: 6),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeContainer.trailingAnchor, constant: -6),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeContainer.centerYAnchor),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: badgeContainer.leadingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),

            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: badgeContainer.leadingAnchor, constant: -8),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3)
        ])
    }

    public func updateSelectionState(isSelected: Bool) {
        let isDark = glassIsDark
        if isSelected {
            titleLabel.textColor = GlassPalette.textPrimary(isDark: isDark)
            subtitleLabel.textColor = GlassPalette.textSecondary(isDark: isDark)
            badgeLabel.textColor = GlassPalette.textPrimary(isDark: isDark)
            badgeContainer.layer?.backgroundColor = isDark
                ? NSColor(white: 1.0, alpha: 0.18).cgColor
                : NSColor(white: 0.0, alpha: 0.10).cgColor
        } else {
            titleLabel.textColor = GlassPalette.textPrimary(isDark: isDark)
            subtitleLabel.textColor = GlassPalette.textSecondary(isDark: isDark)
            badgeLabel.textColor = GlassPalette.textSecondary(isDark: isDark)
            badgeContainer.layer?.backgroundColor = isDark
                ? NSColor(white: 1.0, alpha: 0.07).cgColor
                : NSColor(white: 0.0, alpha: 0.04).cgColor
        }
    }

    public func configure(with result: SearchResult) {
        titleLabel.stringValue = result.title
        subtitleLabel.stringValue = result.subtitle

        switch result.type {
        case .application:
            badgeLabel.stringValue = "应用"
        case .file:
            badgeLabel.stringValue = "文件"
        case .folder:
            badgeLabel.stringValue = "文件夹"
        case .calculator:
            badgeLabel.stringValue = "计算"
        case .dictionary:
            badgeLabel.stringValue = "词典"
        case .systemAction:
            badgeLabel.stringValue = "系统"
        case .webSearch:
            badgeLabel.stringValue = "网络"
        }

        representedIconPath = result.path
        if let icon = result.icon {
            iconView.image = icon
        } else if let path = result.path {
            // Clear the reused cell's previous icon, and ignore late callbacks for a row this
            // cell no longer shows.
            iconView.image = nil
            ThumbnailPipeline.shared.icon(forPath: path) { [weak self] img in
                guard let self = self, self.representedIconPath == path else { return }
                self.iconView.image = img
            }
        } else {
            iconView.image = ThumbnailPipeline.shared.symbolIcon(name: "doc")
        }
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // On first display the inherited appearance may still resolve as light
        // before the dark window appearance propagates. Re-apply colors once
        // the cell is actually in a window so text never flashes black.
        let isSelected = (superview as? SearchResultRowView)?.isSelected ?? false
        updateSelectionState(isSelected: isSelected)
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let isSelected = (superview as? SearchResultRowView)?.isSelected ?? false
        updateSelectionState(isSelected: isSelected)
    }
}

public final class ContextualSearchTableView: NSTableView {
    public weak var owner: SearchResultsTableView?
    private var trackingArea: NSTrackingArea?

    override public var mouseDownCanMoveWindow: Bool { false }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    private var lastMouseScreenLocation: NSPoint?

    /// Called when the result list is (re)shown so a stationary cursor doesn't steal focus.
    public func resetHoverTracking() {
        lastMouseScreenLocation = NSEvent.mouseLocation
    }

    override public func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        // The panel expands underneath a resting cursor; that must not move the keyboard
        // selection away from the top match. Only real pointer movement selects.
        lastMouseScreenLocation = NSEvent.mouseLocation
    }

    override public func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let location = NSEvent.mouseLocation
        if let last = lastMouseScreenLocation, hypot(location.x - last.x, location.y - last.y) < 2 {
            return
        }
        lastMouseScreenLocation = location
        updateSelectionForMouse(event: event)
    }

    private func updateSelectionForMouse(event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        if row >= 0 && row < numberOfRows && row != selectedRow {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    override public func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        guard row >= 0, let owner = owner, row < owner.resultsCount else {
            return super.menu(for: event)
        }

        // Force selection of right-clicked row
        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)

        guard let result = owner.result(at: row) else { return nil }

        let menu = NSMenu(title: "Context")

        if let path = result.path, !path.isEmpty {
            let copyItem = NSMenuItem(title: "📋 复制文件路径", action: #selector(copyFilePathAction(_:)), keyEquivalent: "c")
            copyItem.target = self
            copyItem.representedObject = path
            menu.addItem(copyItem)

            let revealItem = NSMenuItem(title: "📂 在访达中显示", action: #selector(revealInFinderAction(_:)), keyEquivalent: "r")
            revealItem.target = self
            revealItem.representedObject = path
            menu.addItem(revealItem)

            menu.addItem(NSMenuItem.separator())

            let openItem = NSMenuItem(title: "打开", action: #selector(openFileAction(_:)), keyEquivalent: "")
            openItem.image = ThumbnailPipeline.shared.symbolIcon(name: "play", pointSize: 13)
            openItem.target = self
            openItem.representedObject = result
            menu.addItem(openItem)
        } else {
            // Calculator, Dictionary or System Action
            let copyContentItem = NSMenuItem(title: "📋 复制内容", action: #selector(copyContentAction(_:)), keyEquivalent: "c")
            copyContentItem.target = self
            copyContentItem.representedObject = result.title
            menu.addItem(copyContentItem)

            menu.addItem(NSMenuItem.separator())

            let runItem = NSMenuItem(title: "执行或打开", action: #selector(openFileAction(_:)), keyEquivalent: "")
            runItem.image = ThumbnailPipeline.shared.symbolIcon(name: "play", pointSize: 13)
            runItem.target = self
            runItem.representedObject = result
            menu.addItem(runItem)
        }

        return menu
    }

    @objc private func copyFilePathAction(_ sender: NSMenuItem) {
        if let path = sender.representedObject as? String {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        }
        if let owner = owner {
            owner.delegate?.searchResultsTableDidRequestDismiss(owner)
        } else {
            PanelCoordinator.shared.hideAllPanels()
        }
    }

    @objc private func revealInFinderAction(_ sender: NSMenuItem) {
        if let path = sender.representedObject as? String {
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        if let owner = owner {
            owner.delegate?.searchResultsTableDidRequestDismiss(owner)
        } else {
            PanelCoordinator.shared.hideAllPanels()
        }
    }

    @objc private func copyContentAction(_ sender: NSMenuItem) {
        if let text = sender.representedObject as? String {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        if let owner = owner {
            owner.delegate?.searchResultsTableDidRequestDismiss(owner)
        } else {
            PanelCoordinator.shared.hideAllPanels()
        }
    }

    @objc private func openFileAction(_ sender: NSMenuItem) {
        guard let res = sender.representedObject as? SearchResult, let owner = owner else { return }
        owner.delegate?.searchResultsTable(owner, didSelectResult: res, isCommandPressed: false)
    }

    override public func keyDown(with event: NSEvent) {
        let isCmd = event.modifierFlags.contains(.command)
        let isOpt = event.modifierFlags.contains(.option)
        let key = event.charactersIgnoringModifiers?.lowercased()

        if isCmd && !isOpt && key == "r" {
            if let owner = owner, owner.revealSelectedInFinder() {
                owner.delegate?.searchResultsTableDidRequestDismiss(owner)
                return
            }
        } else if isCmd && key == "c" {
            if let owner = owner, owner.copySelectedPath() {
                owner.delegate?.searchResultsTableDidRequestDismiss(owner)
                return
            }
        }
        super.keyDown(with: event)
    }
}

public final class SearchResultRowView: NSTableRowView {
    override public var mouseDownCanMoveWindow: Bool { false }

    override public var isSelected: Bool {
        didSet {
            updateCellColors()
            needsDisplay = true
        }
    }

    override public var isEmphasized: Bool {
        didSet {
            updateCellColors()
            needsDisplay = true
        }
    }

    private func updateCellColors() {
        for sub in subviews {
            if let cell = sub as? SearchResultCellView {
                cell.updateSelectionState(isSelected: isSelected)
            }
        }
    }

    override public func drawSelection(in dirtyRect: NSRect) {
        // Intentionally empty: We draw our custom rounded pill in drawBackground for clean corner clipping
    }

    override public func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard isSelected else { return }

        let isDark = glassIsDark
        let pillRect = bounds.insetBy(dx: 6, dy: 3)
        let path = NSBezierPath(roundedRect: pillRect, xRadius: 10, yRadius: 10)

        if isDark {
            NSColor(white: 1.0, alpha: 0.11).setFill()
        } else {
            NSColor(white: 0.0, alpha: 0.06).setFill()
        }
        path.fill()

        let borderPath = NSBezierPath(roundedRect: pillRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 9.5, yRadius: 9.5)
        let borderColor = isDark ? NSColor(white: 1.0, alpha: 0.14) : NSColor(white: 0.0, alpha: 0.06)
        borderColor.setStroke()
        borderPath.lineWidth = 0.75
        borderPath.stroke()
    }
}

public final class SearchResultsTableView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    public weak var delegate: SearchResultsTableDelegate?

    fileprivate var results: [SearchResult] = []
    private let scrollView = NSScrollView()
    public let tableView = ContextualSearchTableView()

    public var resultsCount: Int {
        return results.count
    }

    public func result(at index: Int) -> SearchResult? {
        guard index >= 0 && index < results.count else { return nil }
        return results[index]
    }

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        addSubview(scrollView)

        tableView.owner = self
        tableView.dataSource = self
        tableView.delegate = self
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.rowHeight = 52
        tableView.selectionHighlightStyle = .none
        tableView.action = #selector(rowClicked)
        tableView.doubleAction = nil
        tableView.target = self
        tableView.setDraggingSourceOperationMask([.copy, .generic], forLocal: false)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ResultColumn"))
        column.isEditable = false
        tableView.addTableColumn(column)

        scrollView.documentView = tableView

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    public func updateResults(_ newResults: [SearchResult]) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updateResults(newResults)
            }
            return
        }

        let previousSelectedId = (tableView.selectedRow >= 0 && tableView.selectedRow < results.count) ? results[tableView.selectedRow].id : nil
        self.results = newResults
        tableView.reloadData()
        tableView.resetHoverTracking()

        if !results.isEmpty {
            // If the previous selection was a temporary webSearch fallback and real files/apps have now arrived, focus the top real match (index 0)
            if let prevId = previousSelectedId,
               !prevId.hasPrefix("web_"),
               let newIdx = results.firstIndex(where: { $0.id == prevId }) {
                tableView.selectRowIndexes(IndexSet(integer: newIdx), byExtendingSelection: false)
                tableView.scrollRowToVisible(newIdx)
            } else {
                tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                tableView.scrollRowToVisible(0)
            }
        }
    }


    public func selectNext() {
        let current = tableView.selectedRow
        let next = min(current + 1, results.count - 1)
        if next >= 0 {
            tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
            tableView.scrollRowToVisible(next)
        }
    }

    public func selectPrevious() {
        let current = tableView.selectedRow
        let prev = max(current - 1, 0)
        if prev < results.count {
            tableView.selectRowIndexes(IndexSet(integer: prev), byExtendingSelection: false)
            tableView.scrollRowToVisible(prev)
        }
    }

    private var isExecuting: Bool = false

    public func copySelectedPath() -> Bool {
        let row = tableView.selectedRow
        guard row >= 0 && row < results.count else { return false }
        let result = results[row]

        if let path = result.path, !path.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
            return true
        } else if result.type == .calculator {
            let rawText = result.title.hasPrefix("= ") ? String(result.title.dropFirst(2)) : result.title
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(rawText, forType: .string)
            return true
        } else if !result.title.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(result.title, forType: .string)
            return true
        }
        return false
    }

    public func revealSelectedInFinder() -> Bool {
        let row = tableView.selectedRow
        guard row >= 0 && row < results.count else { return false }
        let result = results[row]

        if let path = result.path, !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return true
        }
        return false
    }

    public func executeSelected(isCommandPressed: Bool) {
        let row = tableView.selectedRow
        executeResult(at: row, isCommandPressed: isCommandPressed)
    }

    public func executeResult(at row: Int, isCommandPressed: Bool) {
        guard row >= 0 && row < results.count else { return }
        guard !isExecuting else { return }
        isExecuting = true
        let item = results[row]
        delegate?.searchResultsTable(self, didSelectResult: item, isCommandPressed: isCommandPressed)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isExecuting = false
        }
    }

    @objc private func rowClicked() {
        if let event = NSApp.currentEvent, (event.type == .leftMouseUp || event.type == .leftMouseDown) {
            if tableView.clickedRow < 0 { return }
        }
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        guard row >= 0 && row < results.count else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        let isCmd = NSEvent.modifierFlags.contains(.command)
        executeResult(at: row, isCommandPressed: isCmd)
    }

    // MARK: - NSTableViewDataSource & Delegate
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return results.count
    }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let identifier = NSUserInterfaceItemIdentifier("SearchResultRow")
        var rowView = tableView.makeView(withIdentifier: identifier, owner: self) as? SearchResultRowView
        if rowView == nil {
            rowView = SearchResultRowView()
            rowView?.identifier = identifier
        }
        return rowView
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("SearchResultCell")
        var cell = tableView.makeView(withIdentifier: identifier, owner: self) as? SearchResultCellView
        if cell == nil {
            cell = SearchResultCellView(frame: .zero)
            cell?.identifier = identifier
        }
        cell?.configure(with: results[row])
        let isSel = (tableView.selectedRow == row)
        cell?.updateSelectionState(isSelected: isSel)
        return cell
    }

    // MARK: - Drag & Drop Source (External Apps: WeChat, QQ, DingTalk, Finder)
    public func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard row >= 0 && row < results.count else { return nil }
        return results[row].pasteboardWriter
    }

    public func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return context == .withinApplication ? [] : [.copy, .generic]
    }

    private var draggedRow: Int?

    public func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
        PanelCoordinator.shared.isDraggingActive = true
        draggedRow = rowIndexes.first
    }

    public func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        PanelCoordinator.shared.isDraggingActive = false

        // 外部应用成功接收 Drop（如微信输入框、QQ 窗口、访达目录）
        if operation != [] {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let row = self.draggedRow ?? tableView.selectedRow
                self.draggedRow = nil
                guard row >= 0 && row < self.results.count else {
                    PanelCoordinator.shared.hideAllPanels()
                    return
                }
                self.delegate?.searchResultsTable(self, didCompleteDragResult: self.results[row])
            }
        }
    }

    public func tableView(_ tableView: NSTableView, draggingImageComponentsForRow row: Int, at point: NSPoint, with event: NSEvent) -> [NSDraggingImageComponent] {
        guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? SearchResultCellView else {
            return []
        }
        // 构建紧凑优雅的半透明拖拽快照 (包含图标与标题)，避免 680pt 宽条遮挡聊天界面
        let iconBounds = cell.iconView.convert(cell.iconView.bounds, to: cell)
        let titleBounds = cell.titleLabel.convert(cell.titleLabel.bounds, to: cell)
        let dragRect = iconBounds.union(titleBounds).insetBy(dx: -6, dy: -4)

        let snapshot = cell.dataWithPDF(inside: dragRect)
        let img = NSImage(data: snapshot) ?? NSImage()

        let component = NSDraggingImageComponent(key: .icon)
        component.contents = img
        component.frame = NSRect(origin: .zero, size: dragRect.size)
        return [component]
    }
}
