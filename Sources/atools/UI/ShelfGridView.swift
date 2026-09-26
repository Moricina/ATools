import Foundation
import AppKit

public protocol ShelfGridDelegate: AnyObject {
    func shelfGrid(_ grid: ShelfGridView, didLaunchItem item: LauncherItem)
    func shelfGrid(_ grid: ShelfGridView, didDeleteItem item: LauncherItem)
    func shelfGrid(_ grid: ShelfGridView, didAddPaths paths: [String])
    func shelfGrid(_ grid: ShelfGridView, didMoveItemFrom fromIndex: Int, to toIndex: Int)
}

public final class ShelfItemButton: NSControl {
    public let item: LauncherItem
    public var scale: Double {
        didSet {
            updateScaleDimensions()
        }
    }
    public let iconImageView = NSImageView()
    public let titleLabel = NSTextField(labelWithString: "")

    private var iconTopConstraint: NSLayoutConstraint?
    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?

    private var trackingArea: NSTrackingArea?
    private var mouseDownLocation: NSPoint?
    private var isHovered: Bool = false {
        didSet { updateAppearanceStyles() }
    }
    private var isPressed: Bool = false {
        didSet { updateAppearanceStyles() }
    }

    override public var mouseDownCanMoveWindow: Bool { false }

    public init(item: LauncherItem, scale: Double = ConfigManager.shared.config.shelfIconScale, frame: NSRect = .zero) {
        self.item = item
        self.scale = scale
        super.init(frame: frame)
        setupViews()
    }

    public convenience init(item: LauncherItem, iconConfig: ShelfIconSize, frame: NSRect = .zero) {
        let sc: Double
        switch iconConfig {
        case .small: sc = 0.8
        case .large: sc = 1.2
        default: sc = 1.0
        }
        self.init(item: item, scale: sc, frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = false

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconImageView)

        let initialFontSize = max(10, min(14, round(11.0 * scale)))
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: initialFontSize, weight: .regular)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.textColor = .labelColor
        titleLabel.stringValue = item.name
        addSubview(titleLabel)

        toolTip = "\(item.name)\n\(item.target)"

        let topPadding = max(4, round(6.0 * scale))
        let iconSize = round(48.0 * scale)

        let topC = iconImageView.topAnchor.constraint(equalTo: topAnchor, constant: topPadding)
        let widthC = iconImageView.widthAnchor.constraint(equalToConstant: iconSize)
        let heightC = iconImageView.heightAnchor.constraint(equalToConstant: iconSize)
        self.iconTopConstraint = topC
        self.iconWidthConstraint = widthC
        self.iconHeightConstraint = heightC

        NSLayoutConstraint.activate([
            topC,
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            widthC,
            heightC,

            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)
        ])

        ThumbnailPipeline.shared.icon(forPath: item.target) { [weak self] img in
            self?.iconImageView.image = img
        }

        updateAppearanceStyles()
    }

    public func updateScaleDimensions() {
        let iconSize = round(48.0 * scale)
        let fontSize = max(10, min(14, round(11.0 * scale)))
        let topPadding = max(4, round(6.0 * scale))
        iconWidthConstraint?.constant = iconSize
        iconHeightConstraint?.constant = iconSize
        iconTopConstraint?.constant = topPadding
        titleLabel.font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
    }

    private func updateAppearanceStyles() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isPressed {
            layer?.borderWidth = 0.5
            if isDark {
                layer?.backgroundColor = NSColor(white: 0.28, alpha: 0.85).cgColor
                layer?.borderColor = NSColor(white: 1.0, alpha: 0.20).cgColor
            } else {
                layer?.backgroundColor = NSColor(white: 0.0, alpha: 0.12).cgColor
                layer?.borderColor = NSColor(white: 0.0, alpha: 0.15).cgColor
            }
        } else if isHovered {
            layer?.borderWidth = 0.5
            if isDark {
                layer?.backgroundColor = NSColor(white: 0.18, alpha: 0.70).cgColor
                layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor
            } else {
                layer?.backgroundColor = NSColor(white: 0.0, alpha: 0.06).cgColor
                layer?.borderColor = NSColor(white: 0.0, alpha: 0.08).cgColor
            }
        } else {
            layer?.borderWidth = 0.0
            layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceStyles()
    }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override public func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override public func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
    }

    override public func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override public func mouseDown(with event: NSEvent) {
        isPressed = true
        mouseDownLocation = event.locationInWindow
    }

    override public func mouseDragged(with event: NSEvent) {
        guard let startPoint = mouseDownLocation else { return }
        let currentPoint = event.locationInWindow
        let dist = hypot(currentPoint.x - startPoint.x, currentPoint.y - startPoint.y)
        if dist > 5 {
            mouseDownLocation = nil
            isPressed = false
            startDragSession(with: event)
        }
    }

    override public func mouseUp(with event: NSEvent) {
        isPressed = false
        if mouseDownLocation != nil {
            mouseDownLocation = nil
            sendAction(action, to: target)
        }
    }

    override public func rightMouseDown(with event: NSEvent) {
        if let menu = menu {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    private func startDragSession(with event: NSEvent) {
        let pbItem = NSPasteboardItem()
        pbItem.setString(item.id.uuidString, forType: NSPasteboard.PasteboardType(AppConstants.shelfItemReorderType))
        pbItem.setString(item.id.uuidString, forType: NSPasteboard.PasteboardType(AppConstants.shelfItemMoveType))

        let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
        let snapshot = snapshotImage()
        dragItem.setDraggingFrame(bounds, contents: snapshot)

        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    private func snapshotImage() -> NSImage {
        let pdf = dataWithPDF(inside: bounds)
        return NSImage(data: pdf) ?? NSImage()
    }
}

extension ShelfItemButton: NSDraggingSource {
    public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Internal reordering only: never claim .move outside the shelf grid to prevent macOS App Management TCC alerts
        return context == .withinApplication ? .move : []
    }
}

private final class FlippedContentView: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let hit = hitTest(localPoint)
        // If clicking on empty space in contentView (no ShelfItemButton hit), perform window drag
        if hit == self || hit == nil {
            window?.performDrag(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }
}

public final class ShelfGridView: NSView {
    public weak var delegate: ShelfGridDelegate?
    override public var mouseDownCanMoveWindow: Bool { false }

    override public func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        let hit = hitTest(localPoint)
        if hit == self || hit == scrollView || hit == nil {
            window?.performDrag(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }

    internal var items: [LauncherItem] = []
    internal var itemButtons: [ShelfItemButton] = []

    private let scrollView = NSScrollView()
    private let contentView = FlippedContentView()
    private let emptyLabel = NSTextField(labelWithString: "拖拽软件、文件或脚本至此处快速添加")

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
        registerForDraggedTypes([.fileURL, NSPasteboard.PasteboardType(AppConstants.shelfItemReorderType)])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.verticalScroller?.controlSize = .small
        scrollView.drawsBackground = false
        addSubview(scrollView)

        contentView.wantsLayer = true
        scrollView.documentView = contentView

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    override public func layout() {
        super.layout()
        relayoutButtons()
    }

    public func reloadData(items: [LauncherItem]) {
        self.items = items
        emptyLabel.isHidden = !items.isEmpty

        // Remove old buttons
        contentView.subviews.forEach { $0.removeFromSuperview() }
        itemButtons.removeAll()

        guard !items.isEmpty else {
            contentView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
            return
        }

        let scale = ConfigManager.shared.config.shelfIconScale

        for item in items {
            let btn = ShelfItemButton(item: item, scale: scale, frame: .zero)
            btn.target = self
            btn.action = #selector(itemClicked(_:))

            // Standard Cocoa context menu using representedObject
            let menu = NSMenu(title: "ShelfItemMenu")

            let openItem = NSMenuItem(title: "打开", action: #selector(contextOpen(_:)), keyEquivalent: "")
            openItem.target = self
            openItem.representedObject = item
            menu.addItem(openItem)

            let revealItem = NSMenuItem(title: "在访达中显示", action: #selector(contextReveal(_:)), keyEquivalent: "")
            revealItem.target = self
            revealItem.representedObject = item
            menu.addItem(revealItem)

            menu.addItem(NSMenuItem.separator())

            let deleteItem = NSMenuItem(title: "从分类中移除", action: #selector(contextDelete(_:)), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.representedObject = item
            menu.addItem(deleteItem)

            menu.addItem(NSMenuItem.separator())

            let settingsItem = NSMenuItem(title: "⚙️ 偏好设置...", action: #selector(contextOpenSettings), keyEquivalent: "")
            settingsItem.target = self
            menu.addItem(settingsItem)

            btn.menu = menu
            contentView.addSubview(btn)
            itemButtons.append(btn)
        }

        relayoutButtons()
    }

    private func relayoutButtons() {
        guard !itemButtons.isEmpty else { return }

        let scale = ConfigManager.shared.config.shelfIconScale
        let itemWidth: CGFloat = round(82.0 * scale)
        let itemHeight: CGFloat = round(82.0 * scale)
        let iconSize = round(48.0 * scale)
        // Fix side margins to exactly match the app card border padding (distance from icon to card edge)
        let sideMargin: CGFloat = max(10, round((itemWidth - iconSize) / 2.0))
        let topMargin: CGFloat = 12
        let spacingX: CGFloat = 12
        let spacingY: CGFloat = 12
        let bottomSafePadding: CGFloat = 20

        let availableWidth = max(bounds.width, 100)
        let cols = max(1, Int((availableWidth - sideMargin * 2 + spacingX) / (itemWidth + spacingX)))
        let rows = Int(ceil(Double(itemButtons.count) / Double(cols)))

        let totalContentHeight = max(bounds.height, CGFloat(rows) * (itemHeight + spacingY) + topMargin + bottomSafePadding)
        contentView.frame = NSRect(x: 0, y: 0, width: availableWidth, height: totalContentHeight)

        for (index, btn) in itemButtons.enumerated() {
            let col = index % cols
            let row = index / cols
            let x = sideMargin + CGFloat(col) * (itemWidth + spacingX)
            // Flipped coordinates: y starts from top margin
            let y = topMargin + CGFloat(row) * (itemHeight + spacingY)

            btn.frame = NSRect(x: x, y: y, width: itemWidth, height: itemHeight)
        }
    }

    override public func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu(title: "ShelfGridMenu")

        let isPinned = PanelCoordinator.shared.isShelfPinned
        let pinItem = NSMenuItem(
            title: isPinned ? "✓ 固定在桌面" : "固定在桌面",
            action: #selector(contextTogglePin),
            keyEquivalent: ""
        )
        pinItem.target = self
        menu.addItem(pinItem)

        let settingsItem = NSMenuItem(title: "⚙️ 偏好设置...", action: #selector(contextOpenSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())
        let closeItem = NSMenuItem(title: "关闭抽屉", action: #selector(contextCloseShelf), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func contextTogglePin() {
        PanelCoordinator.shared.isShelfPinned.toggle()
    }

    @objc private func contextOpenSettings() {
        SettingsWindowController.shared.showSettingsWindow()
    }

    @objc private func contextCloseShelf() {
        PanelCoordinator.shared.hideAllPanels()
    }

    @objc private func itemClicked(_ sender: ShelfItemButton) {
        delegate?.shelfGrid(self, didLaunchItem: sender.item)
    }

    @objc private func contextOpen(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? LauncherItem else { return }
        delegate?.shelfGrid(self, didLaunchItem: item)
    }

    @objc private func contextReveal(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? LauncherItem else { return }
        NSWorkspace.shared.selectFile(item.target, inFileViewerRootedAtPath: "")
    }

    @objc private func contextDelete(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? LauncherItem else { return }
        delegate?.shelfGrid(self, didDeleteItem: item)
    }

    // MARK: - Drag and Drop Support
    override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        if pboard.types?.contains(NSPasteboard.PasteboardType(AppConstants.shelfItemReorderType)) == true {
            return .move
        }
        if pboard.types?.contains(.fileURL) == true {
            wantsLayer = true
            layer?.cornerRadius = 8
            layer?.borderWidth = 2.0
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.06).cgColor
            return .copy
        }
        return []
    }

    override public func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        if pboard.types?.contains(NSPasteboard.PasteboardType(AppConstants.shelfItemReorderType)) == true {
            return .move
        }
        if pboard.types?.contains(.fileURL) == true {
            return .copy
        }
        return []
    }

    override public func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderWidth = 0.0
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override public func draggingEnded(_ sender: NSDraggingInfo) {
        layer?.borderWidth = 0.0
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderWidth = 0.0
        layer?.backgroundColor = NSColor.clear.cgColor

        let pboard = sender.draggingPasteboard

        // 1. Internal item reordering
        if let idString = pboard.string(forType: NSPasteboard.PasteboardType(AppConstants.shelfItemReorderType)),
           let sourceId = UUID(uuidString: idString),
           let sourceIndex = items.firstIndex(where: { $0.id == sourceId }) {

            let loc = contentView.convert(sender.draggingLocation, from: nil)
            var targetIndex = items.count - 1

            for (idx, btn) in itemButtons.enumerated() {
                if loc.y < btn.frame.maxY && loc.x < btn.frame.maxX {
                    targetIndex = idx
                    break
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.shelfGrid(self, didMoveItemFrom: sourceIndex, to: targetIndex)
            }
            return true
        }

        // 2. External file drop
        let readOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: readOptions) as? [URL] else {
            return false
        }

        let paths = urls.map { $0.path }
        if !paths.isEmpty {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.shelfGrid(self, didAddPaths: paths)
            }
            return true
        }
        return false
    }
}
