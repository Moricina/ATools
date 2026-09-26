import Foundation
import AppKit

public protocol CategoryPillDelegate: AnyObject {
    func categoryPillDidClick(_ pill: CategoryPillView)
    func categoryPillDidRequestRename(_ pill: CategoryPillView)
    func categoryPillDidRequestDelete(_ pill: CategoryPillView)
    func categoryPillDidRequestAdd()
    func categoryPill(_ pill: CategoryPillView, didMoveLauncherItemID id: UUID)
}

public final class CategoryPillView: NSView {
    public weak var delegate: CategoryPillDelegate?
    public let category: Category
    public var isSelected: Bool {
        didSet {
            updateAppearanceStyles()
        }
    }

    private var isHovered: Bool = false {
        didSet {
            updateAppearanceStyles()
        }
    }

    private var isDropTarget: Bool = false {
        didSet {
            updateAppearanceStyles()
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
        layer?.cornerRadius = isVertical ? 7 : 14
        layer?.masksToBounds = true
        registerForDraggedTypes([NSPasteboard.PasteboardType(AppConstants.shelfItemMoveType)])

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

        updateAppearanceStyles()
    }

    public func updateItemCount(_ count: Int) {
        // Count badge removed per user requirement
    }

    private func updateAppearanceStyles() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        // Zero shadow across all states as requested by user
        layer?.shadowOpacity = 0.0
        layer?.shadowColor = nil
        layer?.shadowPath = nil

        if isDropTarget {
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            layer?.borderWidth = 1.5
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            titleLabel.textColor = NSColor.controlAccentColor
        } else if isSelected {
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            layer?.borderWidth = 0.5

            if isDark {
                layer?.backgroundColor = NSColor(white: 0.28, alpha: 0.85).cgColor
                layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor
                titleLabel.textColor = .white
            } else {
                layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.95).cgColor
                layer?.borderColor = NSColor(white: 0.0, alpha: 0.06).cgColor
                titleLabel.textColor = NSColor(white: 0.12, alpha: 1.0)
            }
        } else {
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

            if isHovered {
                layer?.borderWidth = 0.5
                if isDark {
                    layer?.backgroundColor = NSColor(white: 0.18, alpha: 0.7).cgColor
                    layer?.borderColor = NSColor(white: 1.0, alpha: 0.10).cgColor
                    titleLabel.textColor = .labelColor
                } else {
                    layer?.backgroundColor = NSColor(white: 0.0, alpha: 0.06).cgColor
                    layer?.borderColor = NSColor(white: 0.0, alpha: 0.06).cgColor
                    titleLabel.textColor = .labelColor
                }
            } else {
                layer?.borderWidth = 0.0
                layer?.backgroundColor = NSColor.clear.cgColor
                titleLabel.textColor = .secondaryLabelColor
            }
        }
    }

    override public func layout() {
        super.layout()
        updateShadowPath()
    }

    private func updateShadowPath() {
        layer?.shadowOpacity = 0.0
        layer?.shadowColor = nil
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
        pbItem.setString(category.id.uuidString, forType: NSPasteboard.PasteboardType("cc.atools.category-reorder"))

        let dragItem = NSDraggingItem(pasteboardWriter: pbItem)
        let snapshot = snapshotImage()
        dragItem.setDraggingFrame(bounds, contents: snapshot)

        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    private func snapshotImage() -> NSImage {
        let pdf = dataWithPDF(inside: bounds)
        return NSImage(data: pdf) ?? NSImage()
    }

    // MARK: - Drag Destination (Launcher Item Move)
    override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.types?.contains(NSPasteboard.PasteboardType(AppConstants.shelfItemMoveType)) == true else {
            return []
        }
        isDropTarget = true
        return .move
    }

    override public func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.types?.contains(NSPasteboard.PasteboardType(AppConstants.shelfItemMoveType)) == true else {
            return []
        }
        isDropTarget = true
        return .move
    }

    override public func draggingExited(_ sender: NSDraggingInfo?) {
        isDropTarget = false
    }

    override public func draggingEnded(_ sender: NSDraggingInfo) {
        isDropTarget = false
    }

    override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTarget = false
        guard let idString = sender.draggingPasteboard.string(forType: NSPasteboard.PasteboardType(AppConstants.shelfItemMoveType)),
              let id = UUID(uuidString: idString) else {
            return false
        }
        delegate?.categoryPill(self, didMoveLauncherItemID: id)
        return true
    }

    // MARK: - Right Click Context Menu
    override public func rightMouseDown(with event: NSEvent) {
        // Select this category first
        delegate?.categoryPillDidClick(self)

        let menu = NSMenu(title: "CategoryMenu")

        let renameItem = NSMenuItem(title: "✏️ 重命名分类...", action: #selector(contextRename), keyEquivalent: "")
        renameItem.target = self
        menu.addItem(renameItem)

        let deleteItem = NSMenuItem(title: "🗑️ 删除分类", action: #selector(contextDelete), keyEquivalent: "")
        deleteItem.target = self
        // Disable delete if this is the only category
        let totalCategories = ConfigManager.shared.config.categories.count
        if totalCategories <= 1 {
            deleteItem.isEnabled = false
            deleteItem.toolTip = "至少需要保留一个分类"
        }
        menu.addItem(deleteItem)

        menu.addItem(NSMenuItem.separator())

        let addItem = NSMenuItem(title: "➕ 新建分类...", action: #selector(contextAdd), keyEquivalent: "")
        addItem.target = self
        menu.addItem(addItem)

        menu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(title: "⚙️ 偏好设置...", action: #selector(contextOpenSettings), keyEquivalent: ",")
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
