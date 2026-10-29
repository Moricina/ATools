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
    private let titleField = NSTextField()
    private let closeButton = NSButton()
    private let scrollView = NSScrollView()
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
        addSubview(cardContainer)

        // 液态毛玻璃背景
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.addSubview(backdrop)

        // 顶部标题（默认纯文本，双击进入内联重命名）
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
        cardContainer.addSubview(titleField)

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
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = gridContentView
        cardContainer.addSubview(scrollView)

        let widthConstraint = cardContainer.widthAnchor.constraint(equalToConstant: 340)
        widthConstraint.priority = .defaultHigh
        let heightConstraint = cardContainer.heightAnchor.constraint(equalToConstant: 240)
        heightConstraint.priority = .defaultHigh

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

            titleField.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: 14),
            titleField.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 40),
            titleField.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -40),
            titleField.heightAnchor.constraint(equalToConstant: 22),

            closeButton.centerYAnchor.constraint(equalTo: titleField.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -14),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),

            scrollView.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 10),
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

    private func layoutGrid() {
        let cols = 3
        let itemWidth: CGFloat = 96
        let itemHeight: CGFloat = 80
        let spacingX: CGFloat = 10
        let spacingY: CGFloat = 10

        var curX: CGFloat = 0
        var curY: CGFloat = 0

        for (i, btn) in subItemButtons.enumerated() {
            let col = i % cols
            let row = i / cols
            curX = CGFloat(col) * (itemWidth + spacingX)
            curY = CGFloat(row) * (itemHeight + spacingY)
            btn.frame = NSRect(x: curX, y: curY, width: itemWidth, height: itemHeight)
        }

        let totalRows = (subItemButtons.count + cols - 1) / cols
        let totalHeight = max(160, CGFloat(totalRows) * (itemHeight + spacingY))
        gridContentView.frame = NSRect(x: 0, y: 0, width: 310, height: totalHeight)
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
        titleField.isEditable = true
        titleField.isSelectable = true
        window?.makeFirstResponder(titleField)
        titleField.currentEditor()?.selectAll(nil)
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            isCancellingTitleEdit = true
            titleField.stringValue = folderItem.name
            window?.makeFirstResponder(nil)
            titleField.isEditable = false
            titleField.isSelectable = false
            isCancellingTitleEdit = false
            return true
        } else if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            window?.makeFirstResponder(nil)
            titleField.isEditable = false
            titleField.isSelectable = false
            return true
        }
        return false
    }

    public func prepareForClose() {
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
        let newTitle = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newTitle.isEmpty && newTitle != folderItem.name {
            folderItem.name = newTitle
            delegate?.folderOverlay(self, didRenameFolder: folderItem.id, to: newTitle)
        } else {
            titleField.stringValue = folderItem.name
        }
    }

    private final class FlippedGridView: NSView {
        override var isFlipped: Bool { true }
    }
}

private final class FolderCardContainerView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {
        // 阻止点击空白区域冒泡到上层 ShelfRootView 触发窗口拖动
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
