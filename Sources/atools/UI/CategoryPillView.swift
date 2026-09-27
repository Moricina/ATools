import Foundation
import AppKit

public protocol CategoryPillDelegate: AnyObject {
    func categoryPillDidClick(_ pill: CategoryPillView)
    func categoryPillDidRequestRename(_ pill: CategoryPillView)
    func categoryPillDidRequestDelete(_ pill: CategoryPillView)
    func categoryPillDidRequestAdd()
    func categoryPill(_ pill: CategoryPillView, didMoveLauncherItemID id: UUID)
    func categoryPill(_ pill: CategoryPillView, didAddPaths paths: [String])
}

public final class CategoryPillView: NSView {
    public weak var delegate: CategoryPillDelegate?
    public let category: Category
    public var isSelected: Bool {
        didSet {
            if oldValue != isSelected {
                updateAppearanceStyles()
            }
        }
    }

    private var isHovered: Bool = false {
        didSet {
            if oldValue != isHovered {
                updateAppearanceStyles()
            }
        }
    }

    internal var isDropTarget: Bool = false {
        didSet {
            if oldValue != isDropTarget {
                updateAppearanceStyles()
            }
        }
    }

    public let isVertical: Bool
    private let titleLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?

    public init(category: Category, isSelected: Bool, isVertical: Bool = false) {
        self.category = category
        self.isSelected = isSelected
        self.isVertical = isVertical
        super.init(frame: .zero)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        wantsLayer = true
        layer?.cornerRadius = isVertical ? 11 : 15
        layer?.masksToBounds = true
        registerForDraggedTypes([
            NSPasteboard.PasteboardType(AppConstants.shelfItemMoveType),
            .fileURL
        ])

        // Title (Pure text category, zero icon)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = category.name
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.alignment = .center
        addSubview(titleLabel)

        let heightConstant: CGFloat = isVertical ? 29 : 28
        let hPadding: CGFloat = isVertical ? 3 : 14

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: heightConstant),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hPadding),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hPadding),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        setAccessibilityRole(.button)
        setAccessibilityLabel("分类: \(category.name)")
        updateAppearanceStyles()
    }

    public func updateItemCount(_ count: Int) {
        // Count badge removed per user requirement
    }

    private func updateAppearanceStyles() {
        let isDark = glassIsDark

        layer?.shadowOffset = CGSize(width: 0, height: 3)
        layer?.shadowRadius = 8

        // Liquid easing for the background, border and glow so the capsule
        // reads as a flowing glass droplet rather than an instant color swap.
        // View-backed layers ignore CATransaction durations (AppKit returns no action),
        // so implicit animation has to be enabled through NSAnimationContext.
        // One font weight for every state: switching weights changed the pill width and made
        // neighbouring tabs jump while the selection capsule was gliding.
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = window == nil ? 0 : 0.18
        NSAnimationContext.current.timingFunction = CAMediaTimingFunction(name: .easeOut)
        NSAnimationContext.current.allowsImplicitAnimation = true

        if isDropTarget {
            layer?.borderWidth = 0.75
            layer?.borderColor = GlassPalette.panelBorder(isDark: isDark).cgColor
            layer?.backgroundColor = GlassPalette.dropTargetFill(isDark: isDark).cgColor
            layer?.shadowColor = GlassPalette.shadowColor(isDark: isDark).cgColor
            layer?.shadowOpacity = 0.16
            titleLabel.textColor = GlassPalette.textPrimary(isDark: isDark)
        } else if isSelected {
            // The selected background is rendered by the shared flowing capsule
            // in CategoryBarView, so the pill only changes its text here.
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = 0.0
            layer?.shadowOpacity = 0.0
            titleLabel.textColor = GlassPalette.textPrimary(isDark: isDark)
        } else {
            if isHovered {
                layer?.borderWidth = 0.75
                layer?.backgroundColor = GlassPalette.controlHoverFill(isDark: isDark).cgColor
                layer?.borderColor = GlassPalette.panelBorder(isDark: isDark).cgColor
                layer?.shadowColor = nil
                layer?.shadowOpacity = 0.0
                titleLabel.textColor = GlassPalette.textPrimary(isDark: isDark)
            } else {
                layer?.borderWidth = 0.0
                layer?.backgroundColor = NSColor.clear.cgColor
                layer?.shadowColor = nil
                layer?.shadowOpacity = 0.0
                titleLabel.textColor = GlassPalette.textSecondary(isDark: isDark)
            }
        }

        NSAnimationContext.endGrouping()
    }

    override public func layout() {
        super.layout()
        updateShadowPath()
    }

    private func updateShadowPath() {
        // Soft glow without an explicit path: Core Animation falls back to a
        // rounded-rect shadow derived from the layer's corner radius, avoiding
        // the macOS 14+ `cgPath` API while keeping the macOS 12 floor intact.
        layer?.shadowPath = nil
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceStyles()
    }

    override public var isFlipped: Bool { return true }
    override public var mouseDownCanMoveWindow: Bool { false }

    // MARK: - Mouse & Drag Events
    private var mouseDownLocation: NSPoint?

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override public func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override public func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override public func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override public func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override public func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
    }

    override public func mouseDragged(with event: NSEvent) {
        guard let startPoint = mouseDownLocation else { return }
        let currentPoint = event.locationInWindow
        let dist = hypot(currentPoint.x - startPoint.x, currentPoint.y - startPoint.y)
        if dist > 5 {
            mouseDownLocation = nil
            startDragSession(with: event)
        }
    }

    override public func mouseUp(with event: NSEvent) {
        if mouseDownLocation != nil {
            mouseDownLocation = nil
            delegate?.categoryPillDidClick(self)
        }
    }

    private func startDragSession(with event: NSEvent) {
        let pbItem = NSPasteboardItem()
        pbItem.setString(category.id.uuidString, forType: NSPasteboard.PasteboardType(AppConstants.categoryReorderType))

        let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
        let snapshot = snapshotImage()
        dragItem.setDraggingFrame(bounds, contents: snapshot)

        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    private func snapshotImage() -> NSImage {
        let pdf = dataWithPDF(inside: bounds)
        return NSImage(data: pdf) ?? NSImage()
    }

    // MARK: - Drag Destination (Launcher Item Move & External File Drop)
    override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        let isInternalMove = pboard.types?.contains(NSPasteboard.PasteboardType(AppConstants.shelfItemMoveType)) == true
        let isFile = pboard.types?.contains(.fileURL) == true
        guard isInternalMove || isFile else {
            return []
        }
        isDropTarget = true
        return isInternalMove ? .move : .copy
    }

    override public func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        let isInternalMove = pboard.types?.contains(NSPasteboard.PasteboardType(AppConstants.shelfItemMoveType)) == true
        let isFile = pboard.types?.contains(.fileURL) == true
        guard isInternalMove || isFile else {
            return []
        }
        isDropTarget = true
        return isInternalMove ? .move : .copy
    }

    override public func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTarget = false
    }

    override public func draggingEnded(_ sender: NSDraggingInfo) {
        isDropTarget = false
    }

    override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTarget = false

        let pboard = sender.draggingPasteboard

        // 1. Move existing launcher item
        if let idString = pboard.string(forType: NSPasteboard.PasteboardType(AppConstants.shelfItemMoveType)),
           let id = UUID(uuidString: idString) {
            delegate?.categoryPill(self, didMoveLauncherItemID: id)
            return true
        }

        // 2. Drag-and-drop external file / app into category
        let readOptions: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: readOptions) as? [URL], !urls.isEmpty {
            let paths = urls.map { $0.path }
            delegate?.categoryPill(self, didAddPaths: paths)
            return true
        }

        return false
    }

    // MARK: - Right Click Context Menu
    override public func rightMouseDown(with event: NSEvent) {
        // Select this category first
        delegate?.categoryPillDidClick(self)

        let menu = NSMenu(title: "CategoryMenu")

        let renameItem = NSMenuItem(title: "重命名分类...", action: #selector(contextRename), keyEquivalent: "")
        renameItem.image = ThumbnailPipeline.shared.symbolIcon(name: "pencil", pointSize: 13)
        renameItem.target = self
        menu.addItem(renameItem)

        let deleteItem = NSMenuItem(title: "删除分类", action: #selector(contextDelete), keyEquivalent: "")
        deleteItem.image = ThumbnailPipeline.shared.symbolIcon(name: "trash", pointSize: 13)
        deleteItem.target = self
        // Disable delete if this is the only category
        let totalCategories = ConfigManager.shared.config.categories.count
        if totalCategories <= 1 {
            deleteItem.isEnabled = false
            deleteItem.toolTip = "至少需要保留一个分类"
        }
        menu.addItem(deleteItem)

        menu.addItem(NSMenuItem.separator())

        let addItem = NSMenuItem(title: "新建分类...", action: #selector(contextAdd), keyEquivalent: "")
        addItem.image = ThumbnailPipeline.shared.symbolIcon(name: "plus", pointSize: 13)
        addItem.target = self
        menu.addItem(addItem)

        menu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(title: "偏好设置...", action: #selector(contextOpenSettings), keyEquivalent: ",")
        settingsItem.image = ThumbnailPipeline.shared.symbolIcon(name: "gearshape", pointSize: 13)
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        menu.addItem(settingsItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func contextRename() {
        delegate?.categoryPillDidRequestRename(self)
    }

    @objc private func contextDelete() {
        delegate?.categoryPillDidRequestDelete(self)
    }

    @objc private func contextAdd() {
        delegate?.categoryPillDidRequestAdd()
    }

    @objc private func contextOpenSettings() {
        SettingsWindowController.shared.showSettingsWindow()
    }
}

extension CategoryPillView: NSDraggingSource {
    public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return context == .withinApplication ? .move : []
    }
}
