import Foundation
import AppKit

public protocol SearchFilterBarDelegate: AnyObject {
    func searchFilterBar(_ bar: SearchFilterBarView, didSelectFilter filter: SearchTypeFilter)
    func searchFilterBar(_ bar: SearchFilterBarView, didSelectSyntaxCommand command: SearchSyntaxCommand)
}

public final class SearchSyntaxPillButton: NSButton {
    public weak var barView: SearchFilterBarView?
    public let command: SearchSyntaxCommand
    public var isHighlightedPill: Bool = false {
        didSet {
            updateAppearance()
        }
    }
    private var isHovered: Bool = false {
        didSet {
            updateAppearance()
        }
    }
    private var trackingArea: NSTrackingArea?

    public init(command: SearchSyntaxCommand) {
        self.command = command
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        refusesFirstResponder = true
        isBordered = false
        bezelStyle = .inline
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.masksToBounds = true
        title = ""
        toolTip = "\(command.trigger) \(command.name) - \(command.description) (按 Tab 补全)"

        let icon = ThumbnailPipeline.shared.symbolIcon(name: command.iconSymbolName, pointSize: 11, weight: .medium)
        image = icon
        imagePosition = .imageLeading
        imageHugsTitle = true

        updateAppearance()
    }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override public func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
    }

    override public func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
    }

    public func updateAppearance() {
        let isDark = glassIsDark
        let font = NSFont.systemFont(ofSize: 11.5, weight: isHighlightedPill ? .semibold : .medium)
        let textColor: NSColor

        if isHighlightedPill {
            textColor = isDark ? NSColor(red: 0.45, green: 0.75, blue: 1.0, alpha: 1.0) : NSColor(red: 0.05, green: 0.4, blue: 0.9, alpha: 1.0)
            layer?.backgroundColor = isDark
                ? NSColor(red: 0.15, green: 0.45, blue: 0.95, alpha: 0.28).cgColor
                : NSColor(red: 0.05, green: 0.35, blue: 0.85, alpha: 0.12).cgColor
            layer?.borderWidth = 0.85
            layer?.borderColor = isDark
                ? NSColor(red: 0.3, green: 0.6, blue: 1.0, alpha: 0.45).cgColor
                : NSColor(red: 0.1, green: 0.45, blue: 0.95, alpha: 0.30).cgColor
        } else if isHovered {
            textColor = GlassPalette.textPrimary(isDark: isDark)
            layer?.backgroundColor = isDark
                ? NSColor(white: 1.0, alpha: 0.08).cgColor
                : NSColor(white: 0.0, alpha: 0.04).cgColor
            layer?.borderWidth = 0.5
            layer?.borderColor = isDark
                ? NSColor(white: 1.0, alpha: 0.12).cgColor
                : NSColor(white: 0.0, alpha: 0.06).cgColor
        } else {
            textColor = GlassPalette.textSecondary(isDark: isDark)
            layer?.backgroundColor = isDark
                ? NSColor(white: 1.0, alpha: 0.05).cgColor
                : NSColor(white: 0.0, alpha: 0.03).cgColor
            layer?.borderWidth = 0.5
            layer?.borderColor = isDark
                ? NSColor(white: 1.0, alpha: 0.08).cgColor
                : NSColor(white: 0.0, alpha: 0.04).cgColor
        }

        contentTintColor = textColor
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        attributedTitle = NSAttributedString(string: " \(command.trigger) \(command.name)", attributes: [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: style
        ])
    }
}

public final class SearchFilterPillButton: NSButton, NSDraggingSource {
    public weak var barView: SearchFilterBarView?
    public let filter: SearchTypeFilter
    public var isPillSelected: Bool = false {
        didSet {
            updateAppearance()
        }
    }
    private var isHovered: Bool = false {
        didSet {
            updateAppearance()
        }
    }
    private var trackingArea: NSTrackingArea?
    private var mouseDownPoint: NSPoint = .zero
    private var isDraggingSessionActive: Bool = false

    public init(filter: SearchTypeFilter) {
        self.filter = filter
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        refusesFirstResponder = true
        isBordered = false
        bezelStyle = .inline
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.masksToBounds = true
        title = ""
        toolTip = "\(filter.displayName) (可拖动排序)"

        let icon = ThumbnailPipeline.shared.symbolIcon(name: filter.iconSymbolName, pointSize: 11, weight: .medium)
        image = icon
        imagePosition = .imageLeading
        imageHugsTitle = true

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        attributedTitle = NSAttributedString(string: " \(filter.displayName)", attributes: [
            .font: font,
            .paragraphStyle: style
        ])

        updateAppearance()
    }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override public func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
    }

    override public func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
    }

    override public func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        isDraggingSessionActive = false
        layer?.opacity = 0.82
    }

    override public func mouseDragged(with event: NSEvent) {
        guard !isDraggingSessionActive else { return }
        let currentPoint = event.locationInWindow
        let dx = currentPoint.x - mouseDownPoint.x
        let dy = currentPoint.y - mouseDownPoint.y
        if hypot(dx, dy) > 4 {
            isDraggingSessionActive = true
            layer?.opacity = 1.0
            startDrag(with: event)
        }
    }

    override public func mouseUp(with event: NSEvent) {
        layer?.opacity = 1.0
        if !isDraggingSessionActive {
            let pointInView = convert(event.locationInWindow, from: nil)
            if bounds.contains(pointInView) {
                sendAction(action, to: target)
            }
        }
        isDraggingSessionActive = false
    }

    private func createDragSnapshot() -> NSImage {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else {
            return NSImage(size: NSSize(width: 60, height: 26))
        }
        if let bitmapRep = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: bitmapRep)
            let image = NSImage(size: size)
            image.addRepresentation(bitmapRep)
            return image
        }
        let image = NSImage(size: size)
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            layer?.render(in: ctx)
        }
        image.unlockFocus()
        return image
    }

    private func startDrag(with event: NSEvent) {
        guard let bar = barView else { return }
        bar.pillDidBeginDragging(self)

        let pbItem = NSPasteboardItem()
        pbItem.setString(filter.rawValue, forType: SearchFilterBarView.pillDragType)

        let snapshot = createDragSnapshot()
        let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
        dragItem.setDraggingFrame(bounds, contents: snapshot)

        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    // MARK: - NSDraggingSource
    public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return context == .withinApplication ? .move : []
    }

    public func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDraggingSessionActive = false
        layer?.opacity = 1.0
        barView?.pillDidEndDragging(self, operation: operation)
    }

    public func updateAppearance() {
        let isDark = glassIsDark
        let font = NSFont.systemFont(ofSize: 11.5, weight: isPillSelected ? .semibold : .medium)
        let textColor: NSColor

        if isPillSelected {
            textColor = GlassPalette.textPrimary(isDark: isDark)
            layer?.backgroundColor = isDark
                ? NSColor(white: 1.0, alpha: 0.18).cgColor
                : NSColor(white: 0.0, alpha: 0.09).cgColor
            layer?.borderWidth = 0.75
            layer?.borderColor = isDark
                ? NSColor(white: 1.0, alpha: 0.22).cgColor
                : NSColor(white: 0.0, alpha: 0.12).cgColor
        } else if isHovered {
            textColor = GlassPalette.textPrimary(isDark: isDark)
            layer?.backgroundColor = isDark
                ? NSColor(white: 1.0, alpha: 0.08).cgColor
                : NSColor(white: 0.0, alpha: 0.04).cgColor
            layer?.borderWidth = 0.5
            layer?.borderColor = isDark
                ? NSColor(white: 1.0, alpha: 0.12).cgColor
                : NSColor(white: 0.0, alpha: 0.06).cgColor
        } else {
            textColor = GlassPalette.textSecondary(isDark: isDark)
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = 0
            layer?.borderColor = NSColor.clear.cgColor
        }

        contentTintColor = textColor
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        attributedTitle = NSAttributedString(string: " \(filter.displayName)", attributes: [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: style
        ])
    }
}

public enum SearchFilterBarMode: Equatable {
    case typeFilters
    case syntaxCommands
}

public final class SearchFilterBarView: NSView {
    public static let pillDragType = NSPasteboard.PasteboardType("cc.atools.filterPillReorder")

    public weak var delegate: SearchFilterBarDelegate?

    private let stackView = NSStackView()
    private var initialFiltersBeforeDrag: [SearchTypeFilter] = []
    private weak var currentDraggedPill: SearchFilterPillButton?

    public private(set) var currentMode: SearchFilterBarMode = .typeFilters
    private var currentSyntaxCommands: [SearchSyntaxCommand] = []

    public var pillButtons: [SearchFilterPillButton] {
        return stackView.arrangedSubviews.compactMap { $0 as? SearchFilterPillButton }
    }

    public var syntaxButtons: [SearchSyntaxPillButton] {
        return stackView.arrangedSubviews.compactMap { $0 as? SearchSyntaxPillButton }
    }

    public var activeSyntaxCommandForAutocomplete: SearchSyntaxCommand? {
        return currentSyntaxCommands.first
    }

    public var orderedFilters: [SearchTypeFilter] {
        return pillButtons.map(\.filter)
    }

    public var selectedFilter: SearchTypeFilter = .all {
        didSet {
            guard oldValue != selectedFilter else { return }
            updateSelectionState()
        }
    }

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChanged),
            name: .atoolsThemeDidChange,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleThemeChanged() {
        for btn in pillButtons {
            btn.updateAppearance()
        }
        for btn in syntaxButtons {
            btn.updateAppearance()
        }
    }

    private func setupViews() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        registerForDraggedTypes([Self.pillDragType])

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .horizontal
        stackView.distribution = .fillProportionally
        stackView.alignment = .centerY
        stackView.spacing = 4
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        loadPills(from: ConfigManager.shared.config.searchFilterOrder)
    }

    public func loadPills(from orderStrings: [String]) {
        currentMode = .typeFilters
        currentSyntaxCommands = []

        for subview in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        let filters = SearchTypeFilter.resolvedOrder(from: orderStrings)
        for filter in filters {
            let btn = SearchFilterPillButton(filter: filter)
            btn.barView = self
            btn.target = self
            btn.action = #selector(pillClicked(_:))
            btn.isPillSelected = (filter == selectedFilter)
            btn.setContentHuggingPriority(.required, for: .horizontal)
            btn.setContentCompressionResistancePriority(.required, for: .horizontal)
            stackView.addArrangedSubview(btn)

            btn.heightAnchor.constraint(equalToConstant: 26).isActive = true
        }
    }

    // MARK: - Syntax Commands Mode
    public func showSyntaxCommands(_ commands: [SearchSyntaxCommand]) {
        currentMode = .syntaxCommands
        currentSyntaxCommands = commands

        for subview in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        guard !commands.isEmpty else {
            let label = NSTextField(labelWithString: "无匹配的语法指令")
            label.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
            label.textColor = GlassPalette.textTertiary(isDark: glassIsDark)
            stackView.addArrangedSubview(label)
            return
        }

        // Display up to 7 commands that fit comfortably in the capsule bar
        for (index, cmd) in commands.prefix(7).enumerated() {
            let btn = SearchSyntaxPillButton(command: cmd)
            btn.barView = self
            btn.isHighlightedPill = (index == 0) // First is primed for Tab
            btn.target = self
            btn.action = #selector(syntaxPillClicked(_:))
            btn.setContentHuggingPriority(.required, for: .horizontal)
            btn.setContentCompressionResistancePriority(.required, for: .horizontal)
            stackView.addArrangedSubview(btn)
            btn.heightAnchor.constraint(equalToConstant: 26).isActive = true
        }
    }

    public func showTypeFilters() {
        guard currentMode != .typeFilters else { return }
        loadPills(from: ConfigManager.shared.config.searchFilterOrder)
    }

    @objc private func syntaxPillClicked(_ sender: SearchSyntaxPillButton) {
        delegate?.searchFilterBar(self, didSelectSyntaxCommand: sender.command)
    }

    @objc private func pillClicked(_ sender: SearchFilterPillButton) {
        let newFilter = sender.filter
        guard selectedFilter != newFilter else { return }
        selectedFilter = newFilter
        delegate?.searchFilterBar(self, didSelectFilter: newFilter)
    }

    private func updateSelectionState() {
        for btn in pillButtons {
            btn.isPillSelected = (btn.filter == selectedFilter)
        }
    }

    // MARK: - Drag and Drop Handling (Active only in typeFilters mode)
    internal func pillDidBeginDragging(_ pill: SearchFilterPillButton) {
        guard currentMode == .typeFilters else { return }
        initialFiltersBeforeDrag = orderedFilters
        currentDraggedPill = pill
        pill.alphaValue = 0.35
    }

    internal func pillDidEndDragging(_ pill: SearchFilterPillButton, operation: NSDragOperation) {
        guard currentMode == .typeFilters else { return }
        pill.alphaValue = 1.0
        currentDraggedPill = nil
        if operation == [] {
            restoreOrder(initialFiltersBeforeDrag)
        } else {
            commitCurrentOrder()
        }
    }

    private func commitCurrentOrder() {
        let newOrder = orderedFilters
        ConfigManager.shared.updateSearchFilterOrder(newOrder.map(\.rawValue))
    }

    private func restoreOrder(_ filters: [SearchTypeFilter]) {
        let currentPills = pillButtons
        var pillMap: [SearchTypeFilter: SearchFilterPillButton] = [:]
        for pill in currentPills {
            pillMap[pill.filter] = pill
        }
        for pill in currentPills {
            stackView.removeArrangedSubview(pill)
        }
        for filter in filters {
            if let pill = pillMap[filter] {
                stackView.addArrangedSubview(pill)
            }
        }
        stackView.layoutSubtreeIfNeeded()
    }

    override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard currentMode == .typeFilters else { return [] }
        guard sender.draggingPasteboard.types?.contains(Self.pillDragType) == true else { return [] }
        return .move
    }

    override public func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard currentMode == .typeFilters else { return [] }
        guard sender.draggingPasteboard.types?.contains(Self.pillDragType) == true else { return [] }
        guard let dragged = currentDraggedPill else { return [] }

        let pointInBar = convert(sender.draggingLocation, from: nil)
        let currentSubviews = pillButtons
        guard let currentIndex = currentSubviews.firstIndex(of: dragged) else { return .move }

        let others = currentSubviews.filter { $0 !== dragged }
        var targetIndex = others.count
        for (idx, other) in others.enumerated() {
            let otherFrame = other.convert(other.bounds, to: self)
            if pointInBar.x < otherFrame.midX {
                targetIndex = idx
                break
            }
        }

        if targetIndex != currentIndex {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.allowsImplicitAnimation = true
                stackView.removeArrangedSubview(dragged)
                stackView.insertArrangedSubview(dragged, at: targetIndex)
                stackView.layoutSubtreeIfNeeded()
            }
        }

        return .move
    }

    override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard currentMode == .typeFilters else { return false }
        guard let dragged = currentDraggedPill else { return false }
        dragged.alphaValue = 1.0
        currentDraggedPill = nil
        commitCurrentOrder()
        return true
    }

    // MARK: - Shortcut & Navigation Support
    /// 顺时针或逆时针循环切换分类（按当前视觉胶囊顺序支持 Tab / Shift+Tab）
    public func cycleFilter(forward: Bool = true) {
        guard currentMode == .typeFilters else { return }
        let currentOrder = orderedFilters
        guard !currentOrder.isEmpty else { return }
        guard let idx = currentOrder.firstIndex(of: selectedFilter) else {
            let nextFilter = currentOrder[0]
            selectedFilter = nextFilter
            delegate?.searchFilterBar(self, didSelectFilter: nextFilter)
            return
        }
        let nextIdx = forward
            ? (idx + 1) % currentOrder.count
            : (idx - 1 + currentOrder.count) % currentOrder.count
        let nextFilter = currentOrder[nextIdx]
        selectedFilter = nextFilter
        delegate?.searchFilterBar(self, didSelectFilter: nextFilter)
    }

    /// 通过 ⌘1~8 快捷跳转（按照当前视觉呈现的前后顺序）
    public func selectFilter(number: Int) {
        guard currentMode == .typeFilters else { return }
        let currentOrder = orderedFilters
        let index = number - 1
        guard index >= 0 && index < currentOrder.count else { return }
        let nextFilter = currentOrder[index]
        guard selectedFilter != nextFilter else { return }
        selectedFilter = nextFilter
        delegate?.searchFilterBar(self, didSelectFilter: nextFilter)
    }
}
