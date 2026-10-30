import Foundation
import AppKit

public protocol ShelfFolderOverlayDelegate: AnyObject {
    func folderOverlayDidRequestClose(_ overlay: ShelfFolderOverlayView)
    func folderOverlay(_ overlay: ShelfFolderOverlayView, didRenameFolder folderId: UUID, to newName: String)
    func folderOverlay(_ overlay: ShelfFolderOverlayView, didRemoveItemFromFolder itemId: UUID, folderId: UUID)
    func folderOverlay(_ overlay: ShelfFolderOverlayView, didSelectItem item: LauncherItem)
}

/// 原生液态磨砂文件夹展开面板（对标 Launchpad 文件夹展开体验）
public final class ShelfFolderOverlayView: NSView, NSTextFieldDelegate {
    public weak var delegate: ShelfFolderOverlayDelegate?

    public private(set) var folderItem: LauncherItem
    public private(set) var subItems: [LauncherItem] = []
    public let categoryId: UUID

    private let dimBackdropView = FolderDimBackdropView()
    private let cardContainer = FolderCardContainerView()
    private let backdrop = VisualEffectBackdropView()
    let titleCapsuleView = TitleCapsuleContainerView()
    private let titleField = NSTextField()
    private let closeButton = NSButton()
    let scrollView = ModernScrollView()
    private let gridContentView = FlippedGridView()
    private var subItemButtons: [ShelfItemButton] = []
    private var isCancellingTitleEdit = false

    override public var mouseDownCanMoveWindow: Bool { false }

    override public func mouseDown(with event: NSEvent) {
        // 截断 Responder 链，阻止点击浮层空白区域冒泡到 ShelfRootView
    }

    override public func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    public init(folderItem: LauncherItem, subItems: [LauncherItem], categoryId: UUID, frame: NSRect = .zero) {
        self.folderItem = folderItem
        self.subItems = subItems
        self.categoryId = categoryId
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        wantsLayer = true
        autoresizingMask = [.width, .height]

        // 半透明暗色背景遮罩，精准点击自动关闭
        dimBackdropView.wantsLayer = true
        dimBackdropView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        dimBackdropView.translatesAutoresizingMaskIntoConstraints = false
        dimBackdropView.onValidClick = { [weak self] in
            self?.handleBackdropClicked()
        }
        addSubview(dimBackdropView)

        // 居中卡片容器
        cardContainer.wantsLayer = true
        cardContainer.layer?.cornerRadius = 20
        cardContainer.layer?.masksToBounds = false
        cardContainer.layer?.shadowColor = NSColor.black.cgColor
        cardContainer.layer?.shadowOpacity = 0.22
        cardContainer.layer?.shadowOffset = CGSize(width: 0, height: -4)
        cardContainer.layer?.shadowRadius = 16
        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.onBlankClicked = { [weak self] in
            self?.dismissEditingIfNeeded()
        }
        addSubview(cardContainer)

        // 液态毛玻璃背景
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(backdrop)

        // 顶部标题晶体输入胶囊（双击改名唤醒聚焦环，悬停微光手形）
        titleCapsuleView.translatesAutoresizingMaskIntoConstraints = false
        titleCapsuleView.isDark = glassIsDark
        titleCapsuleView.onDoubleClicked = { [weak self] in
            self?.beginEditingTitle()
        }
        cardContainer.addSubview(titleCapsuleView)

        // 顶部标题（放入胶囊内部，垂直绝对居中锁定基线）
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.stringValue = folderItem.name.isEmpty ? "未命名文件夹" : folderItem.name
        titleField.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleField.textColor = GlassPalette.textPrimary(isDark: glassIsDark)
        titleField.alignment = .center
        titleField.isBezeled = false
        titleField.drawsBackground = false
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.focusRingType = .none
        titleField.delegate = self
        let doubleClickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleTitleDoubleClicked))
        doubleClickGesture.numberOfClicksRequired = 2
        titleField.addGestureRecognizer(doubleClickGesture)
        titleCapsuleView.addSubview(titleField)

        // 关闭按钮
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.isBordered = false
        closeButton.bezelStyle = .regularSquare
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "关闭")
        closeButton.contentTintColor = GlassPalette.textSecondary(isDark: glassIsDark)
        closeButton.target = self
        closeButton.action = #selector(handleCloseClicked)
        cardContainer.addSubview(closeButton)

        // 滚动与网格区
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.verticalScroller = KnobOnlyScroller()
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = gridContentView
        cardContainer.addSubview(scrollView)

        let widthConstraint = cardContainer.widthAnchor.constraint(equalToConstant: 340)
        widthConstraint.priority = .defaultHigh
        let heightConstraint = cardContainer.heightAnchor.constraint(equalToConstant: 240)
        heightConstraint.priority = .defaultHigh

        let capsuleWidth = titleCapsuleView.widthAnchor.constraint(equalToConstant: 200)
        capsuleWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            dimBackdropView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimBackdropView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dimBackdropView.topAnchor.constraint(equalTo: topAnchor),
            dimBackdropView.bottomAnchor.constraint(equalTo: bottomAnchor),

            cardContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            cardContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthConstraint,
            heightConstraint,
            cardContainer.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -16),
            cardContainer.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor, constant: -16),

            backdrop.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: cardContainer.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor),

            titleCapsuleView.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: 11),
            titleCapsuleView.centerXAnchor.constraint(equalTo: cardContainer.centerXAnchor),
            titleCapsuleView.heightAnchor.constraint(equalToConstant: 28),
            capsuleWidth,
            titleCapsuleView.widthAnchor.constraint(lessThanOrEqualTo: cardContainer.widthAnchor, constant: -80),

            titleField.leadingAnchor.constraint(equalTo: titleCapsuleView.leadingAnchor, constant: 8),
            titleField.trailingAnchor.constraint(equalTo: titleCapsuleView.trailingAnchor, constant: -8),
            titleField.centerYAnchor.constraint(equalTo: titleCapsuleView.centerYAnchor),
            titleField.heightAnchor.constraint(equalToConstant: 22),

            closeButton.centerYAnchor.constraint(equalTo: titleCapsuleView.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -14),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),

            scrollView.topAnchor.constraint(equalTo: titleCapsuleView.bottomAnchor, constant: 9),
            scrollView.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor, constant: -12)
        ])

        reloadSubItems(subItems)
    }

    public func reloadSubItems(_ items: [LauncherItem]) {
        self.subItems = items
        for btn in subItemButtons {
            btn.removeFromSuperview()
        }
        subItemButtons.removeAll()

        for item in items {
            let btn = ShelfItemButton(item: item, scale: 0.85)
            btn.target = self
            btn.action = #selector(handleItemClicked(_:))
            btn.menu = makeContextMenu(for: item)
            gridContentView.addSubview(btn)
            subItemButtons.append(btn)
            ThumbnailPipeline.shared.icon(forItem: item) { [weak btn] image in
                btn?.iconImageView.image = image
            }
        }
        layoutGrid()
    }

    override public func layout() {
        super.layout()
        layoutGrid()
    }

    private func layoutGrid() {
        let cols = 3
        let itemWidth: CGFloat = 96
        let itemHeight: CGFloat = 80
        let spacingX: CGFloat = 10
        let spacingY: CGFloat = 10

        let availableWidth = scrollView.bounds.width > 0 ? scrollView.bounds.width : 316
        let contentWidth = max(316, availableWidth)
        let totalGridWidth = CGFloat(cols) * itemWidth + CGFloat(cols - 1) * spacingX
        let offsetX = max(0, (contentWidth - totalGridWidth) / 2)

        var curX: CGFloat = 0
        var curY: CGFloat = 0

        for (i, btn) in subItemButtons.enumerated() {
            let col = i % cols
            let row = i / cols
            curX = offsetX + CGFloat(col) * (itemWidth + spacingX)
            curY = CGFloat(row) * (itemHeight + spacingY)
            btn.frame = NSRect(x: curX, y: curY, width: itemWidth, height: itemHeight)
        }

        let totalRows = (subItemButtons.count + cols - 1) / cols
        let totalHeight = max(160, CGFloat(totalRows) * (itemHeight + spacingY))
        gridContentView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: totalHeight)
    }

    private func makeContextMenu(for item: LauncherItem) -> NSMenu {
        let menu = NSMenu()
        let openItem = NSMenuItem(title: "打开", action: #selector(contextOpenItem(_:)), keyEquivalent: "")
        openItem.target = self
        openItem.representedObject = item
        menu.addItem(openItem)

        let removeItem = NSMenuItem(title: "移出文件夹", action: #selector(contextRemoveItem(_:)), keyEquivalent: "")
        removeItem.target = self
        removeItem.representedObject = item
        menu.addItem(removeItem)
        return menu
    }

    @objc private func contextOpenItem(_ sender: NSMenuItem) {
        if let item = sender.representedObject as? LauncherItem {
            delegate?.folderOverlay(self, didSelectItem: item)
        }
    }

    @objc private func contextRemoveItem(_ sender: NSMenuItem) {
        if let item = sender.representedObject as? LauncherItem {
            delegate?.folderOverlay(self, didRemoveItemFromFolder: item.id, folderId: folderItem.id)
        }
    }

    @objc private func handleItemClicked(_ sender: ShelfItemButton) {
        delegate?.folderOverlay(self, didSelectItem: sender.item)
    }

    @objc private func handleTitleDoubleClicked() {
        beginEditingTitle()
    }

    public func beginEditingTitle() {
        guard !titleCapsuleView.isEditing else { return }
        titleCapsuleView.isEditing = true
        titleField.isEditable = true
        titleField.isSelectable = true
        window?.makeFirstResponder(titleField)
        titleField.currentEditor()?.selectAll(nil)
    }

    public func dismissEditingIfNeeded() {
        guard titleCapsuleView.isEditing else { return }
        if window?.firstResponder === titleField || window?.firstResponder === titleField.currentEditor() {
            window?.makeFirstResponder(nil)
        }
        finishEditingTitle()
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            isCancellingTitleEdit = true
            titleField.stringValue = folderItem.name
            window?.makeFirstResponder(nil)
            titleField.isEditable = false
            titleField.isSelectable = false
            titleCapsuleView.isEditing = false
            isCancellingTitleEdit = false
            return true
        } else if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            window?.makeFirstResponder(nil)
            titleField.isEditable = false
            titleField.isSelectable = false
            titleCapsuleView.isEditing = false
            return true
        }
        return false
    }

    public func prepareForClose() {
        titleCapsuleView.isEditing = false
        if window?.firstResponder === titleField || window?.firstResponder === titleField.currentEditor() {
            window?.makeFirstResponder(nil)
        }
    }

    @objc private func handleBackdropClicked() {
        prepareForClose()
        finishEditingTitle()
        delegate?.folderOverlayDidRequestClose(self)
    }

    @objc private func handleCloseClicked() {
        prepareForClose()
        finishEditingTitle()
        delegate?.folderOverlayDidRequestClose(self)
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        finishEditingTitle()
    }

    private func finishEditingTitle() {
        guard !isCancellingTitleEdit else { return }
        titleField.isEditable = false
        titleField.isSelectable = false
        titleCapsuleView.isEditing = false
        var newTitle = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if newTitle.count > 24 {
            newTitle = String(newTitle.prefix(24))
        }
        if !newTitle.isEmpty && newTitle != folderItem.name {
            folderItem.name = newTitle
            titleField.stringValue = newTitle
            delegate?.folderOverlay(self, didRenameFolder: folderItem.id, to: newTitle)
        } else {
            titleField.stringValue = folderItem.name
        }
    }

    private final class FlippedGridView: NSView {
        override var isFlipped: Bool { true }
    }
}

final class TitleCapsuleContainerView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    var onDoubleClicked: (() -> Void)?
    var isEditing: Bool = false {
        didSet {
            if oldValue != isEditing {
                updateAppearance(animated: true)
            }
        }
    }
    var isHovered: Bool = false {
        didSet {
            if oldValue != isHovered && !isEditing {
                updateAppearance(animated: true)
            }
        }
    }
    var isDark: Bool = false {
        didSet {
            updateAppearance(animated: false)
        }
    }

    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = false
        toolTip = "双击以重命名"
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick))
        doubleClick.numberOfClicksRequired = 2
        addGestureRecognizer(doubleClick)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleDoubleClick() {
        onDoubleClicked?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        if !isEditing {
            NSCursor.pointingHand.set()
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        if !isEditing {
            NSCursor.arrow.set()
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if !isEditing && isHovered {
            NSCursor.pointingHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 8, cornerHeight: 8, transform: nil)
    }

    func updateAppearance(animated: Bool) {
        guard let layer = self.layer else { return }

        let targetBgColor: CGColor
        let targetBorderColor: CGColor
        let targetBorderWidth: CGFloat
        let targetShadowOpacity: Float

        if isEditing {
            if isDark {
                targetBgColor = NSColor(white: 0.16, alpha: 0.90).cgColor
                targetBorderColor = NSColor.controlAccentColor.withAlphaComponent(0.80).cgColor
            } else {
                targetBgColor = NSColor.white.withAlphaComponent(0.92).cgColor
                targetBorderColor = NSColor.controlAccentColor.withAlphaComponent(0.75).cgColor
            }
            targetBorderWidth = 1.5
            targetShadowOpacity = 0.16
        } else if isHovered {
            if isDark {
                targetBgColor = NSColor.white.withAlphaComponent(0.08).cgColor
                targetBorderColor = NSColor.white.withAlphaComponent(0.18).cgColor
            } else {
                targetBgColor = NSColor.black.withAlphaComponent(0.05).cgColor
                targetBorderColor = NSColor.black.withAlphaComponent(0.10).cgColor
            }
            targetBorderWidth = 1.0
            targetShadowOpacity = 0.0
        } else {
            targetBgColor = NSColor.clear.cgColor
            targetBorderColor = NSColor.clear.cgColor
            targetBorderWidth = 0.0
            targetShadowOpacity = 0.0
        }

        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: -2)
        layer.shadowRadius = 6

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.backgroundColor = targetBgColor
                layer.borderColor = targetBorderColor
                layer.borderWidth = targetBorderWidth
                layer.shadowOpacity = targetShadowOpacity
            }
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.backgroundColor = targetBgColor
            layer.borderColor = targetBorderColor
            layer.borderWidth = targetBorderWidth
            layer.shadowOpacity = targetShadowOpacity
            CATransaction.commit()
        }
    }
}

private final class FolderCardContainerView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    var onBlankClicked: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onBlankClicked?()
    }
}

private final class FolderDimBackdropView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    var onValidClick: (() -> Void)?
    private var downPoint: NSPoint?

    override func mouseDown(with event: NSEvent) {
        downPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseUp(with event: NSEvent) {
        defer { downPoint = nil }
        guard let down = downPoint else { return }
        let up = convert(event.locationInWindow, from: nil)
        let dist = hypot(up.x - down.x, up.y - down.y)
        if dist < 4.0 && bounds.contains(up) {
            onValidClick?()
        }
    }
}
