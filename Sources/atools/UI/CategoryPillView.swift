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

    internal var isSpringLoadingHovered: Bool = false {
        didSet {
            guard oldValue != isSpringLoadingHovered else { return }
            let scale: CGFloat = isSpringLoadingHovered ? (isVertical ? 1.025 : 1.045) : 1.0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                ctx.allowsImplicitAnimation = true
                if isSpringLoadingHovered {
                    layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
                } else {
                    layer?.setAffineTransform(.identity)
                }
            }
            updateAppearanceStyles()
        }
    }

    public let isVertical: Bool
    internal let titleLabel = NSTextField(labelWithString: "")
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
        layer?.masksToBounds = false

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

    private var pillIsDark: Bool {
        if let win = window {
            let app = win.appearance ?? win.effectiveAppearance
            if let match = app.bestMatch(from: [.darkAqua, .aqua]) {
                return match == .darkAqua
            }
        }
        return ConfigManager.shared.config.theme.isDark
    }

    internal func updateAppearanceStyles() {
        let isDark = pillIsDark

        layer?.shadowOffset = CGSize(width: 0, height: 3)
        layer?.shadowRadius = 8

        // Liquid easing for the background, border and glow so the capsule
        // reads as a flowing glass droplet rather than an instant color swap.
        // View-backed layers ignore CATransaction durations (AppKit returns no action),
        // so implicit animation has to be enabled through NSAnimationContext.
        // One font weight for every state: switching weights changed the pill width and made
        // neighbouring tabs jump while the selection capsule was gliding.
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .medium)
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = window == nil ? 0 : 0.18
        NSAnimationContext.current.timingFunction = CAMediaTimingFunction(name: .easeOut)
        NSAnimationContext.current.allowsImplicitAnimation = true

        let primaryTextColor = isDark ? NSColor(white: 1.0, alpha: 1.0) : NSColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 1.0)
        let secondaryTextColor = isDark ? NSColor(white: 1.0, alpha: 0.88) : NSColor(white: 0.15, alpha: 0.78)

        if isSpringLoadingHovered {
            layer?.borderWidth = 1.0
            let highlightBorder = isDark ? NSColor.white.withAlphaComponent(0.65) : NSColor.black.withAlphaComponent(0.40)
            layer?.borderColor = highlightBorder.cgColor
            layer?.backgroundColor = GlassPalette.dropTargetFill(isDark: isDark).cgColor
            layer?.shadowColor = GlassPalette.shadowColor(isDark: isDark).cgColor
            layer?.shadowOpacity = isDark ? 0.35 : 0.20
            layer?.shadowRadius = 10
            titleLabel.textColor = primaryTextColor
        } else if isDropTarget {
            layer?.borderWidth = 0.75
            layer?.borderColor = GlassPalette.panelBorder(isDark: isDark).cgColor
            layer?.backgroundColor = GlassPalette.dropTargetFill(isDark: isDark).cgColor
            layer?.shadowColor = GlassPalette.shadowColor(isDark: isDark).cgColor
            layer?.shadowOpacity = 0.16
            layer?.shadowRadius = 8
            titleLabel.textColor = primaryTextColor
        } else if isSelected {
            // The selected background is rendered by the shared flowing capsule
            // in CategoryBarView, so the pill only changes its text here.
            layer?.backgroundColor = NSColor.clear.cgColor
            layer?.borderWidth = 0.0
            layer?.shadowOpacity = 0.0
            titleLabel.textColor = primaryTextColor
        } else {
            if isHovered {
                layer?.borderWidth = 0.75
                layer?.backgroundColor = GlassPalette.controlHoverFill(isDark: isDark).cgColor
                layer?.borderColor = GlassPalette.panelBorder(isDark: isDark).cgColor
                layer?.shadowColor = nil
                layer?.shadowOpacity = 0.0
                titleLabel.textColor = primaryTextColor
            } else {
                layer?.borderWidth = 0.0
                layer?.backgroundColor = NSColor.clear.cgColor
                layer?.shadowColor = nil
                layer?.shadowOpacity = 0.0
                titleLabel.textColor = secondaryTextColor
            }
        }

        if isDark {
            let sh = NSShadow()
            sh.shadowColor = NSColor.black.withAlphaComponent(isNativeLiquidTheme ? 0.70 : 0.50)
            sh.shadowOffset = NSSize(width: 0, height: -1)
            sh.shadowBlurRadius = isNativeLiquidTheme ? 2.0 : 1.5
            titleLabel.shadow = sh
        } else {
            titleLabel.shadow = nil
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

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearanceStyles()
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

    public func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        PanelCoordinator.shared.isDraggingActive = true
    }

    public func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        PanelCoordinator.shared.isDraggingActive = false
    }
}
