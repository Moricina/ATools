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

    private let dimBackdropView = NSView()
    private let cardContainer = NSView()
    private let backdrop = VisualEffectBackdropView()
    private let titleField = NSTextField()
    private let closeButton = NSButton()
    private let scrollView = NSScrollView()
    private let gridContentView = FlippedGridView()
    private var subItemButtons: [ShelfItemButton] = []

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

        // 半透明暗色背景遮罩，点击自动关闭
        dimBackdropView.wantsLayer = true
        dimBackdropView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        dimBackdropView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dimBackdropView)

        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleBackdropClicked))
        dimBackdropView.addGestureRecognizer(clickGesture)

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

        // 顶部标题（支持内联重命名）
        titleField.translatesAutoresizingMaskIntoConstraints = false
        titleField.stringValue = folderItem.name.isEmpty ? "未命名文件夹" : folderItem.name
        titleField.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleField.textColor = GlassPalette.textPrimary(isDark: glassIsDark)
        titleField.alignment = .center
        titleField.isBezeled = false
        titleField.drawsBackground = false
        titleField.isEditable = true
        titleField.isSelectable = true
        titleField.focusRingType = .none
        titleField.delegate = self
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

        NSLayoutConstraint.activate([
            dimBackdropView.leadingAnchor.constraint(equalTo: leadingAnchor),
            dimBackdropView.trailingAnchor.constraint(equalTo: trailingAnchor),
            dimBackdropView.topAnchor.constraint(equalTo: topAnchor),
            dimBackdropView.bottomAnchor.constraint(equalTo: bottomAnchor),

            cardContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            cardContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            cardContainer.widthAnchor.constraint(equalToConstant: 340),
            cardContainer.heightAnchor.constraint(equalToConstant: 240),

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

    @objc private func handleBackdropClicked() {
        finishEditingTitle()
        delegate?.folderOverlayDidRequestClose(self)
    }

    @objc private func handleCloseClicked() {
        finishEditingTitle()
        delegate?.folderOverlayDidRequestClose(self)
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        finishEditingTitle()
    }

    private func finishEditingTitle() {
        let newTitle = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newTitle.isEmpty && newTitle != folderItem.name {
            folderItem.name = newTitle
            delegate?.folderOverlay(self, didRenameFolder: folderItem.id, to: newTitle)
        }
    }

    private final class FlippedGridView: NSView {
        override var isFlipped: Bool { true }
    }
}
