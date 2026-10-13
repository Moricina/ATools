import Foundation
import AppKit

public protocol SearchFilterBarDelegate: AnyObject {
    func searchFilterBar(_ bar: SearchFilterBarView, didSelectFilter filter: SearchTypeFilter)
    func searchFilterBar(_ bar: SearchFilterBarView, didSelectSyntaxCommand command: SearchSyntaxCommand)
}

private class NonInteractiveLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private class NonInteractiveImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
    private let liquidBackdrop = NativeLiquidSelectionBackdrop(cornerRadius: 6)
    private let iconImageView = NonInteractiveImageView()
    private let titleLabel = NonInteractiveLabel(labelWithString: "")

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
        layer?.cornerRadius = 6
        layer?.masksToBounds = false
        title = ""
        toolTip = "\(command.trigger) \(command.name) - \(command.description) (按 Tab 补全)"

        let icon = ThumbnailPipeline.shared.symbolIcon(name: command.iconSymbolName, pointSize: 11, weight: .medium)
        iconImageView.image = icon
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconImageView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.stringValue = command.name
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        addSubview(titleLabel)

        liquidBackdrop.contactShadowEnabled = true
        liquidBackdrop.customShadowRadius = 4.0
        liquidBackdrop.customShadowOpacity = 0.04
        liquidBackdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(liquidBackdrop, positioned: .below, relativeTo: iconImageView)

        NSLayoutConstraint.activate([
            liquidBackdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            liquidBackdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            liquidBackdrop.topAnchor.constraint(equalTo: topAnchor),
            liquidBackdrop.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 12),
            iconImageView.heightAnchor.constraint(equalToConstant: 12),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateAppearance()
    }

    override public var intrinsicContentSize: NSSize {
        let textWidth = titleLabel.intrinsicContentSize.width
        return NSSize(width: max(40, 7 + 12 + 4 + textWidth + 7), height: 24)
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

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearance()
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    public func updateAppearance() {
        let isDark = glassIsDark
        let isNative = isNativeLiquidTheme
        let font = NSFont.systemFont(ofSize: 12, weight: isHighlightedPill ? .semibold : .medium)
        let textColor: NSColor

        if isNative {
            if isHighlightedPill {
                liquidBackdrop.isHidden = false
                liquidBackdrop.isSelected = true
                liquidBackdrop.isHovered = false
                liquidBackdrop.isDark = isDark
                liquidBackdrop.customShadowOpacity = isDark ? 0.12 : 0.04
                liquidBackdrop.customShadowRadius = 4.0
                liquidBackdrop.updateStyles()
                layer?.backgroundColor = NSColor.clear.cgColor
                layer?.borderWidth = 0.0
                textColor = isDark ? NSColor(white: 1.0, alpha: 1.0) : NSColor(white: 0.10, alpha: 1.0)
            } else if isHovered {
                liquidBackdrop.isHidden = false
                liquidBackdrop.isSelected = false
                liquidBackdrop.isHovered = true
                liquidBackdrop.isDark = isDark
                liquidBackdrop.customShadowOpacity = isDark ? 0.08 : 0.03
                liquidBackdrop.customShadowRadius = 3.5
                liquidBackdrop.updateStyles()
                layer?.backgroundColor = NSColor.clear.cgColor
                layer?.borderWidth = 0.0
                textColor = isDark ? NSColor(white: 1.0, alpha: 1.0) : NSColor(white: 0.12, alpha: 1.0)
            } else {
                liquidBackdrop.isHidden = true
                layer?.backgroundColor = isDark ? NSColor.white.withAlphaComponent(0.06).cgColor : NSColor.white.withAlphaComponent(0.18).cgColor
                layer?.borderWidth = 0.5
                layer?.borderColor = isDark ? NSColor.white.withAlphaComponent(0.12).cgColor : NSColor.white.withAlphaComponent(0.35).cgColor
                textColor = isDark ? NSColor(white: 0.90, alpha: 0.85) : NSColor(white: 0.20, alpha: 0.75)
            }
        } else {
            liquidBackdrop.isHidden = true
            if isHighlightedPill {
                textColor = isDark ? NSColor(white: 1.0, alpha: 1.0) : NSColor(white: 0.05, alpha: 1.0)
                layer?.backgroundColor = isDark
                    ? NSColor.white.withAlphaComponent(0.20).cgColor
                    : NSColor.black.withAlphaComponent(0.10).cgColor
                layer?.borderWidth = 0.5
                layer?.borderColor = isDark
                    ? NSColor.white.withAlphaComponent(0.32).cgColor
                    : NSColor.black.withAlphaComponent(0.18).cgColor
            } else if isHovered {
                textColor = isDark ? NSColor(white: 1.0, alpha: 1.0) : NSColor(white: 0.08, alpha: 1.0)
                layer?.backgroundColor = isDark
                    ? NSColor.white.withAlphaComponent(0.12).cgColor
                    : NSColor.black.withAlphaComponent(0.06).cgColor
                layer?.borderWidth = 0.5
                layer?.borderColor = isDark
                    ? NSColor.white.withAlphaComponent(0.20).cgColor
                    : NSColor.black.withAlphaComponent(0.12).cgColor
            } else {
                textColor = isDark ? NSColor(white: 0.92, alpha: 0.88) : NSColor(white: 0.15, alpha: 0.75)
                layer?.backgroundColor = isDark
                    ? NSColor.white.withAlphaComponent(0.05).cgColor
                    : NSColor.black.withAlphaComponent(0.03).cgColor
                layer?.borderWidth = 0.5
                layer?.borderColor = isDark
                    ? NSColor.white.withAlphaComponent(0.10).cgColor
                    : NSColor.black.withAlphaComponent(0.06).cgColor
            }
        }

        iconImageView.contentTintColor = textColor
        titleLabel.textColor = textColor
        titleLabel.font = font
        if isNative && isDark && isHighlightedPill {
            let sh = NSShadow()
            sh.shadowColor = NSColor.black.withAlphaComponent(0.60)
            sh.shadowOffset = NSSize(width: 0, height: -1)
            sh.shadowBlurRadius = 2.0
            titleLabel.shadow = sh
        } else {
            titleLabel.shadow = nil
        }
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
    private let liquidBackdrop = NativeLiquidSelectionBackdrop(cornerRadius: 6)
    private let iconImageView = NonInteractiveImageView()
    private let titleLabel = NonInteractiveLabel(labelWithString: "")

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
        layer?.cornerRadius = 6
        layer?.masksToBounds = false
        title = ""
        toolTip = "\(filter.displayName) (可拖动排序)"

        let icon = ThumbnailPipeline.shared.symbolIcon(name: filter.iconSymbolName, pointSize: 11, weight: .medium)
        iconImageView.image = icon
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconImageView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.stringValue = filter.displayName
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        addSubview(titleLabel)

        liquidBackdrop.contactShadowEnabled = false
        liquidBackdrop.translatesAutoresizingMaskIntoConstraints = false
        addSubview(liquidBackdrop, positioned: .below, relativeTo: iconImageView)

        NSLayoutConstraint.activate([
            liquidBackdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            liquidBackdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            liquidBackdrop.topAnchor.constraint(equalTo: topAnchor),
            liquidBackdrop.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 12),
            iconImageView.heightAnchor.constraint(equalToConstant: 12),

            titleLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateAppearance()
    }

    override public var intrinsicContentSize: NSSize {
        let textWidth = titleLabel.intrinsicContentSize.width
        return NSSize(width: max(40, 7 + 12 + 4 + textWidth + 7), height: 24)
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

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearance()
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    public func updateAppearance() {
        let isDark = glassIsDark
        let isNative = isNativeLiquidTheme
        let font = NSFont.systemFont(ofSize: 12, weight: isPillSelected ? .semibold : .medium)
        let textColor: NSColor

        if isNative {
            if isPillSelected {
                liquidBackdrop.isHidden = false
                liquidBackdrop.isSelected = true
                liquidBackdrop.isHovered = false
                liquidBackdrop.isDark = isDark
                liquidBackdrop.updateStyles()
                layer?.backgroundColor = NSColor.clear.cgColor
                layer?.borderWidth = 0.0
                textColor = isDark ? NSColor(white: 1.0, alpha: 1.0) : NSColor(white: 0.10, alpha: 1.0)
            } else if isHovered {
                liquidBackdrop.isHidden = false
                liquidBackdrop.isSelected = false
                liquidBackdrop.isHovered = true
                liquidBackdrop.isDark = isDark
                liquidBackdrop.updateStyles()
                layer?.backgroundColor = NSColor.clear.cgColor
                layer?.borderWidth = 0.0
                textColor = isDark ? NSColor(white: 1.0, alpha: 1.0) : NSColor(white: 0.12, alpha: 1.0)
            } else {
                liquidBackdrop.isHidden = true
                layer?.backgroundColor = isDark ? NSColor.white.withAlphaComponent(0.06).cgColor : NSColor.white.withAlphaComponent(0.18).cgColor
                layer?.borderWidth = 0.5
                layer?.borderColor = isDark ? NSColor.white.withAlphaComponent(0.12).cgColor : NSColor.white.withAlphaComponent(0.35).cgColor
                textColor = isDark ? NSColor(white: 0.90, alpha: 0.85) : NSColor(white: 0.20, alpha: 0.75)
            }
        } else {
            liquidBackdrop.isHidden = true
            if isPillSelected {
                textColor = isDark ? NSColor(white: 1.0, alpha: 1.0) : NSColor(white: 0.05, alpha: 1.0)
                layer?.backgroundColor = isDark
                    ? NSColor.white.withAlphaComponent(0.20).cgColor
                    : NSColor.black.withAlphaComponent(0.10).cgColor
                layer?.borderWidth = 0.5
                layer?.borderColor = isDark
                    ? NSColor.white.withAlphaComponent(0.32).cgColor
                    : NSColor.black.withAlphaComponent(0.18).cgColor
            } else if isHovered {
                textColor = isDark ? NSColor(white: 1.0, alpha: 1.0) : NSColor(white: 0.08, alpha: 1.0)
                layer?.backgroundColor = isDark
                    ? NSColor.white.withAlphaComponent(0.12).cgColor
                    : NSColor.black.withAlphaComponent(0.06).cgColor
                layer?.borderWidth = 0.5
                layer?.borderColor = isDark
                    ? NSColor.white.withAlphaComponent(0.20).cgColor
                    : NSColor.black.withAlphaComponent(0.12).cgColor
            } else {
                textColor = isDark ? NSColor(white: 0.92, alpha: 0.88) : NSColor(white: 0.15, alpha: 0.75)
                layer?.backgroundColor = isDark
                    ? NSColor.white.withAlphaComponent(0.05).cgColor
                    : NSColor.black.withAlphaComponent(0.03).cgColor
                layer?.borderWidth = 0.5
                layer?.borderColor = isDark
                    ? NSColor.white.withAlphaComponent(0.10).cgColor
                    : NSColor.black.withAlphaComponent(0.06).cgColor
            }
        }

        iconImageView.contentTintColor = textColor
        titleLabel.textColor = textColor
        titleLabel.font = font
        if isNative && isDark && isPillSelected {
            let sh = NSShadow()
            sh.shadowColor = NSColor.black.withAlphaComponent(0.60)
            sh.shadowOffset = NSSize(width: 0, height: -1)
            sh.shadowBlurRadius = 2.0
            titleLabel.shadow = sh
        } else {
            titleLabel.shadow = nil
        }
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

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updatePillsAppearance()
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updatePillsAppearance()
    }

    @objc private func handleThemeChanged() {
        updatePillsAppearance()
    }

    public func updatePillsAppearance() {
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
        stackView.spacing = 8
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

            btn.heightAnchor.constraint(equalToConstant: 24).isActive = true
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
            btn.heightAnchor.constraint(equalToConstant: 24).isActive = true
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
