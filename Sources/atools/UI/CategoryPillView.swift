import Foundation
import AppKit

public protocol CategoryPillDelegate: AnyObject {
    func categoryPillDidClick(_ pill: CategoryPillView)
    func categoryPillDidRequestRename(_ pill: CategoryPillView)
    func categoryPillDidRequestDelete(_ pill: CategoryPillView)
    func categoryPillDidRequestAdd()
    func categoryPill(_ pill: CategoryPillView, didMoveLauncherItemID id: UUID)
    func categoryPill(_ pill: CategoryPillView, didAddPaths paths: [String])
    func categoryPillDidChangeText(_ pill: CategoryPillView)
    func categoryPillDidCommitEditing(_ pill: CategoryPillView, name: String?)
    func categoryPillDidCancelEditing(_ pill: CategoryPillView)
    func categoryPillJumpMenuItem(_ pill: CategoryPillView) -> NSMenuItem?
}

public extension CategoryPillDelegate {
    func categoryPillDidChangeText(_ pill: CategoryPillView) {}
    func categoryPillDidCommitEditing(_ pill: CategoryPillView, name: String?) {}
    func categoryPillDidCancelEditing(_ pill: CategoryPillView) {}
    func categoryPillJumpMenuItem(_ pill: CategoryPillView) -> NSMenuItem? { return nil }
}

/// 🌟 原生分类胶囊就地内联单行编辑框
internal final class InlineCategoryTextField: NSTextField {
    override func selectText(_ sender: Any?) {
        super.selectText(sender)
        // 关键防护：重写默认全选，将光标定位至末尾（基于 UTF-16 NSString.length 防 Emoji 截断与崩溃）
        let utf16Len = (stringValue as NSString).length
        currentEditor()?.selectedRange = NSRange(location: utf16Len, length: 0)
    }

    @objc func paste(_ sender: Any?) {
        if let raw = NSPasteboard.general.string(forType: .string) {
            let sanitized = CategorySanitizer.sanitize(raw) ?? ""
            let remaining = max(0, CategorySanitizer.maxNameLength - stringValue.count)
            let toInsert = String(sanitized.prefix(remaining))
            if let editor = currentEditor() as? NSTextView {
                editor.insertText(toInsert, replacementRange: editor.selectedRange())
            } else {
                stringValue = toInsert
            }
        }
    }
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

    public private(set) var isEditing: Bool = false
    public var isPendingNew: Bool = false
    private var originalNameBeforeEditing: String = ""
    private var minWidthConstraint: NSLayoutConstraint?

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
    internal let inlineTextField = InlineCategoryTextField()
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
        layer?.cornerRadius = isVertical ? 11 : 13
        layer?.masksToBounds = false

        // Title (Pure text category, zero icon)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = category.name
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.alignment = .center
        addSubview(titleLabel)

        // 🌟 原位就地编辑输入框 (Inline Text Field)
        inlineTextField.translatesAutoresizingMaskIntoConstraints = false
        inlineTextField.isBordered = false
        inlineTextField.drawsBackground = false
        if let cell = inlineTextField.cell as? NSTextFieldCell {
            cell.drawsBackground = false
            cell.backgroundColor = .clear
        }
        inlineTextField.focusRingType = .none
        inlineTextField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        inlineTextField.alignment = .center
        inlineTextField.maximumNumberOfLines = 1
        inlineTextField.lineBreakMode = .byClipping
        inlineTextField.delegate = self
        inlineTextField.isHidden = true
        addSubview(inlineTextField)

        let heightConstant: CGFloat = isVertical ? 29 : 26
        let hPadding: CGFloat = isVertical ? 3 : 14

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: heightConstant),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hPadding),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hPadding),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            inlineTextField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: hPadding),
            inlineTextField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -hPadding),
            inlineTextField.centerYAnchor.constraint(equalTo: centerYAnchor)
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

        let px = physicalOnePixel
        if isSpringLoadingHovered {
            layer?.borderWidth = px * 1.5
            let highlightBorder = isDark ? NSColor.white.withAlphaComponent(0.65) : NSColor.black.withAlphaComponent(0.40)
            layer?.borderColor = highlightBorder.cgColor
            layer?.backgroundColor = GlassPalette.dropTargetFill(isDark: isDark).cgColor
            layer?.shadowColor = GlassPalette.shadowColor(isDark: isDark).cgColor
            layer?.shadowOpacity = isDark ? 0.35 : 0.20
            layer?.shadowRadius = 10
            titleLabel.textColor = primaryTextColor
        } else if isDropTarget {
            layer?.borderWidth = px
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
                layer?.borderWidth = px
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
            sh.shadowColor = NSColor.black.withAlphaComponent(isNativeLiquidTheme ? 0.68 : 0.40)
            sh.shadowOffset = NSSize(width: 0, height: -1.0)
            sh.shadowBlurRadius = isNativeLiquidTheme ? 1.5 : 1.2
            titleLabel.shadow = sh
        } else {
            if isNativeLiquidTheme {
                let sh = NSShadow()
                sh.shadowColor = NSColor.white.withAlphaComponent(0.65)
                sh.shadowOffset = NSSize(width: 0, height: 0.5)
                sh.shadowBlurRadius = 1.0
                titleLabel.shadow = sh
            } else {
                // 磨砂玻璃 (浅色)：在纯白白瓷浮动胶囊上，取消白色光晕阴影，呈现最为纯净锐利的黑字印刷质感
                titleLabel.shadow = nil
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

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearanceStyles()
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceStyles()
    }

    override public func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
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

    // MARK: - In-Place Inline Editing
    internal func updateEditingWidth() {
        guard isEditing, !isVertical else { return }
        let text = inlineTextField.stringValue
        let font = inlineTextField.font ?? NSFont.systemFont(ofSize: 13, weight: .semibold)
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let hPadding: CGFloat = isVertical ? 3 : 14
        let targetWidth = max(76, ceil(textWidth) + hPadding * 2 + 12)
        if let constraint = minWidthConstraint {
            constraint.constant = targetWidth
        } else {
            let constraint = widthAnchor.constraint(equalToConstant: targetWidth)
            constraint.isActive = true
            minWidthConstraint = constraint
        }
    }

    public func beginEditing(cursorAtEnd: Bool) {
        guard !isEditing else { return }
        isEditing = true
        originalNameBeforeEditing = titleLabel.stringValue.isEmpty ? category.name : titleLabel.stringValue

        let isDark = pillIsDark
        inlineTextField.textColor = isDark ? .white : GlassPalette.textPrimary(isDark: false)
        inlineTextField.stringValue = isPendingNew ? "" : originalNameBeforeEditing

        inlineTextField.placeholderAttributedString = nil
        inlineTextField.placeholderString = nil

        titleLabel.isHidden = true
        inlineTextField.isHidden = false

        updateEditingWidth()

        window?.makeFirstResponder(inlineTextField)

        // 基于 UTF-16 NSString.length 精确设置光标位置，杜绝 Emoji 截断与底层异常
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isEditing else { return }
            let utf16Len = cursorAtEnd ? (self.inlineTextField.stringValue as NSString).length : 0
            if let textView = self.inlineTextField.currentEditor() as? NSTextView {
                textView.alignment = .center
                textView.selectedRange = NSRange(location: utf16Len, length: 0)
            } else {
                self.inlineTextField.currentEditor()?.selectedRange = NSRange(location: utf16Len, length: 0)
            }
        }
    }

    @discardableResult
    public func commitEditing() -> String? {
        guard isEditing else { return nil }
        isEditing = false
        minWidthConstraint?.isActive = false
        minWidthConstraint = nil
        inlineTextField.isHidden = true
        titleLabel.isHidden = false

        if window?.firstResponder == inlineTextField || window?.firstResponder == inlineTextField.currentEditor() {
            window?.makeFirstResponder(self)
        }

        let raw = inlineTextField.stringValue
        let safeName = CategorySanitizer.sanitize(raw)
        if let safe = safeName, !safe.isEmpty {
            titleLabel.stringValue = safe
            return safe
        } else {
            titleLabel.stringValue = originalNameBeforeEditing
            return nil
        }
    }

    public func cancelEditing() {
        guard isEditing else { return }
        isEditing = false
        minWidthConstraint?.isActive = false
        minWidthConstraint = nil
        inlineTextField.isHidden = true
        titleLabel.stringValue = originalNameBeforeEditing
        titleLabel.isHidden = false

        if window?.firstResponder == inlineTextField || window?.firstResponder == inlineTextField.currentEditor() {
            window?.makeFirstResponder(self)
        }
    }

    override public func hitTest(_ point: NSPoint) -> NSView? {
        if isEditing {
            let p = superview != nil ? convert(point, from: superview) : point
            if bounds.contains(p) || bounds.contains(point) {
                return inlineTextField
            }
        }
        return super.hitTest(point)
    }

    override public func resetCursorRects() {
        super.resetCursorRects()
        if !isEditing {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override public func mouseEntered(with event: NSEvent) {
        if isEditing { return }
        isHovered = true
    }

    override public func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override public func cursorUpdate(with event: NSEvent) {
        if !isEditing {
            NSCursor.pointingHand.set()
        }
    }

    override public func mouseDown(with event: NSEvent) {
        if isEditing { return }
        mouseDownLocation = event.locationInWindow
    }

    override public func mouseDragged(with event: NSEvent) {
        if isEditing { return }
        guard let startPoint = mouseDownLocation else { return }
        let currentPoint = event.locationInWindow
        let dist = hypot(currentPoint.x - startPoint.x, currentPoint.y - startPoint.y)
        if dist > 5 {
            mouseDownLocation = nil
            startDragSession(with: event)
        }
    }

    override public func mouseUp(with event: NSEvent) {
        if isEditing { return }
        if mouseDownLocation != nil {
            mouseDownLocation = nil
            if event.clickCount == 2 {
                // 双击分类胶囊直接进入重命名
                delegate?.categoryPillDidRequestRename(self)
            } else {
                delegate?.categoryPillDidClick(self)
            }
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

        if let jumpItem = delegate?.categoryPillJumpMenuItem(self) {
            menu.addItem(jumpItem)
        }

        menu.addItem(NSMenuItem.separator())

        let isPinned = PanelCoordinator.shared.isShelfPinned
        let pinItem = NSMenuItem(
            title: isPinned ? "✓ 固定在桌面" : "固定在桌面",
            action: #selector(contextTogglePin),
            keyEquivalent: ""
        )
        pinItem.target = self
        menu.addItem(pinItem)

        let isIconsHidden = DesktopIconManager.shared.isDesktopIconsHidden
        let desktopIconsItem = NSMenuItem(
            title: isIconsHidden ? "✓ 隐藏桌面图标" : "隐藏桌面图标",
            action: #selector(contextToggleDesktopIcons),
            keyEquivalent: ""
        )
        desktopIconsItem.image = ThumbnailPipeline.shared.symbolIcon(name: isIconsHidden ? "eye.slash.fill" : "eye.slash", pointSize: 13)
        desktopIconsItem.target = self
        menu.addItem(desktopIconsItem)

        let settingsItem = NSMenuItem(title: "偏好设置...", action: #selector(contextOpenSettings), keyEquivalent: ",")
        settingsItem.image = ThumbnailPipeline.shared.symbolIcon(name: "gearshape", pointSize: 13)
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())
        let closeItem = NSMenuItem(title: "关闭抽屉", action: #selector(contextCloseShelf), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)

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

    @objc private func contextTogglePin() {
        PanelCoordinator.shared.isShelfPinned.toggle()
    }

    @objc private func contextToggleDesktopIcons() {
        _ = DesktopIconManager.shared.toggleDesktopIcons()
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }

    @objc private func contextOpenSettings() {
        SettingsWindowController.shared.showSettingsWindow()
    }

    @objc private func contextCloseShelf() {
        PanelCoordinator.shared.hideShelfPanel(forceHidePinned: true)
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

extension CategoryPillView: NSTextFieldDelegate {
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if textView.hasMarkedText() {
            return false
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let result = commitEditing()
            delegate?.categoryPillDidCommitEditing(self, name: result)
            return true
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelEditing()
            delegate?.categoryPillDidCancelEditing(self)
            return true
        }
        return false
    }

    public func controlTextDidChange(_ obj: Notification) {
        let text = inlineTextField.stringValue
        if text.count > CategorySanitizer.maxNameLength {
            NSSound.beep()
            let trimmed = String(text.prefix(CategorySanitizer.maxNameLength))
            inlineTextField.stringValue = trimmed
        }
        updateEditingWidth()
        delegate?.categoryPillDidChangeText(self)
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        if isEditing {
            let result = commitEditing()
            delegate?.categoryPillDidCommitEditing(self, name: result)
        }
    }
}

