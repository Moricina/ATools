import Foundation
import AppKit

public final class ModernHeaderButton: NSButton {
    private var trackingArea: NSTrackingArea?

    public var isHovered: Bool = false {
        didSet { updateAppearanceStyles() }
    }

    public var isAccentActive: Bool = false {
        didSet { updateAppearanceStyles() }
    }

    public var isCloseStyle: Bool = false {
        didSet { updateAppearanceStyles() }
    }

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 13 // 26x26 circular glass button
        bezelStyle = .regularSquare
        isBordered = false
        imagePosition = .imageOnly
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate]
        let t = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingArea = t
    }

    override public func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override public func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override public func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override public func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    public func updateAppearanceStyles() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if isAccentActive {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
            layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.40).cgColor
            layer?.borderWidth = 0.5
            contentTintColor = .controlAccentColor
        } else if isHovered {
            if isCloseStyle {
                layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.18).cgColor
                layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.35).cgColor
                layer?.borderWidth = 0.5
                contentTintColor = .systemRed
            } else {
                layer?.backgroundColor = isDark
                    ? NSColor(white: 1.0, alpha: 0.16).cgColor
                    : NSColor(white: 0.0, alpha: 0.08).cgColor
                layer?.borderColor = isDark
                    ? NSColor(white: 1.0, alpha: 0.22).cgColor
                    : NSColor(white: 0.0, alpha: 0.12).cgColor
                layer?.borderWidth = 0.5
                contentTintColor = .labelColor
            }
        } else {
            layer?.backgroundColor = isDark
                ? NSColor(white: 1.0, alpha: 0.06).cgColor
                : NSColor(white: 0.0, alpha: 0.04).cgColor
            layer?.borderColor = isDark
                ? NSColor(white: 1.0, alpha: 0.10).cgColor
                : NSColor(white: 0.0, alpha: 0.06).cgColor
            layer?.borderWidth = 0.5
            contentTintColor = .secondaryLabelColor
        }
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearanceStyles()
    }
}

public final class SidebarSplitterView: NSView {
    override public var mouseDownCanMoveWindow: Bool { false }

    public var onWidthDelta: ((CGFloat) -> Void)?
    public var onDragFinished: (() -> Void)?

    private var isDragging = false
    private var isHovered = false {
        didSet { needsDisplay = true }
    }
    private var initialMouseX: CGFloat = 0
    private var trackingArea: NSTrackingArea?

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

    override public func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override public func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    override public func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSCursor.resizeLeftRight.set()
    }

    override public func mouseExited(with event: NSEvent) {
        isHovered = false
        if !isDragging {
            NSCursor.arrow.set()
        }
    }

    override public func mouseDown(with event: NSEvent) {
        isDragging = true
        NSCursor.resizeLeftRight.push()
        initialMouseX = NSEvent.mouseLocation.x
        needsDisplay = true
    }

    override public func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let currentX = NSEvent.mouseLocation.x
        let delta = currentX - initialMouseX
        initialMouseX = currentX
        onWidthDelta?(delta)
    }

    override public func mouseUp(with event: NSEvent) {
        if isDragging {
            NSCursor.pop()
            isDragging = false
            needsDisplay = true
            onDragFinished?()
        }
    }

    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let midX = bounds.midX
        let lineColor: CGColor
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

        if isDragging {
            lineColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
        } else if isHovered {
            lineColor = isDark
                ? NSColor.white.withAlphaComponent(0.35).cgColor
                : NSColor.black.withAlphaComponent(0.28).cgColor
        } else {
            lineColor = isDark
                ? NSColor.white.withAlphaComponent(0.12).cgColor
                : NSColor.black.withAlphaComponent(0.08).cgColor
        }

        context.setStrokeColor(lineColor)
        context.setLineWidth(1.0)
        context.move(to: CGPoint(x: midX, y: bounds.minY + 4))
        context.addLine(to: CGPoint(x: midX, y: bounds.maxY - 4))
        context.strokePath()
    }
}

public final class ResizeHandleView: NSView {
    // Crucial: prevent isMovableByWindowBackground from hijacking mouse drag events
    override public var mouseDownCanMoveWindow: Bool { false }

    private static var diagonalCursor: NSCursor = {
        let sel = NSSelectorFromString("_windowResizeNorthEastSouthWestCursor")
        if NSCursor.responds(to: sel), let obj = NSCursor.perform(sel)?.takeUnretainedValue() as? NSCursor {
            return obj
        }
        return NSCursor.crosshair
    }()

    private var isDragging = false
    private var isHovered = false {
        didSet { needsDisplay = true }
    }
    private var initialMouseLocation: NSPoint = .zero
    private var initialWindowFrame: NSRect = .zero
    private var trackingArea: NSTrackingArea?

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

    override public func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: ResizeHandleView.diagonalCursor)
    }

    override public func cursorUpdate(with event: NSEvent) {
        ResizeHandleView.diagonalCursor.set()
    }

    override public func mouseEntered(with event: NSEvent) {
        isHovered = true
        ResizeHandleView.diagonalCursor.set()
    }

    override public func mouseExited(with event: NSEvent) {
        isHovered = false
        if !isDragging {
            NSCursor.arrow.set()
        }
    }

    override public func mouseDown(with event: NSEvent) {
        guard let window = self.window else { return }
        isDragging = true
        ResizeHandleView.diagonalCursor.push()
        initialMouseLocation = NSEvent.mouseLocation
        initialWindowFrame = window.frame
        needsDisplay = true
    }

    override public func mouseDragged(with event: NSEvent) {
        guard isDragging, let window = self.window else { return }
        let currentMouse = NSEvent.mouseLocation
        let deltaX = currentMouse.x - initialMouseLocation.x
        let deltaY = currentMouse.y - initialMouseLocation.y

        // Dynamic minimum width based on icon size & orientation to prevent impossible huge gaps
        let config = ConfigManager.shared.config
        let scale = config.shelfIconScale
        let itemWidth: CGFloat = round(82.0 * scale)
        let iconSize: CGFloat = round(48.0 * scale)
        let sideMargin: CGFloat = max(10, round((itemWidth - iconSize) / 2.0))
        let spacingX: CGFloat = 12
        let isVertical = config.categoryOrientation == .vertical
        let sidebarW: CGFloat = isVertical ? 10 + CGFloat(config.sidebarWidth) + 2 + 8 + 8 : 28
        let minContentW: CGFloat = 2 * itemWidth + spacingX + sideMargin * 2
        let minWidth: CGFloat = max(240, sidebarW + minContentW)

        let newWidth = max(minWidth, min(1400, initialWindowFrame.width + deltaX))
        let newHeight = max(180, min(900, initialWindowFrame.height - deltaY))

        // Keep top (maxY) constant and extend downward
        let newOriginY = initialWindowFrame.maxY - newHeight
        let newFrame = NSRect(x: initialWindowFrame.origin.x, y: newOriginY, width: newWidth, height: newHeight)
        window.setFrame(newFrame, display: true)
    }

    override public func mouseUp(with event: NSEvent) {
        if isDragging {
            NSCursor.pop()
            isDragging = false
            needsDisplay = true
            guard let window = self.window else { return }

            // Snap window width smoothly to exact columns on drag release so right margin perfectly matches left margin
            let config = ConfigManager.shared.config
            let scale = config.shelfIconScale
            let itemWidth: CGFloat = round(82.0 * scale)
            let iconSize: CGFloat = round(48.0 * scale)
            let sideMargin: CGFloat = max(10, round((itemWidth - iconSize) / 2.0))
            let spacingX: CGFloat = 12
            let isVertical = config.categoryOrientation == .vertical
            let sidebarW: CGFloat = isVertical ? 10 + CGFloat(config.sidebarWidth) + 2 + 8 + 8 : 28

            let availableW = max(100, window.frame.width - sidebarW)
            let rawCols = (availableW - sideMargin * 2 + spacingX) / (itemWidth + spacingX)
            let targetCols = max(2, Int(round(rawCols)))
            let snappedContentW = CGFloat(targetCols) * itemWidth + CGFloat(targetCols - 1) * spacingX + sideMargin * 2
            let snappedWidth = min(1400, sidebarW + snappedContentW)

            let finalFrame = NSRect(x: window.frame.origin.x, y: window.frame.origin.y, width: snappedWidth, height: window.frame.height)
            window.setFrame(finalFrame, display: true, animate: true)
            ConfigManager.shared.updateShelfSize(width: snappedWidth, height: window.frame.height)
        }
    }

    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Draw 3 delicate diagonal grip lines in the bottom-right corner
        let alpha: CGFloat = isHovered ? 0.75 : (isDragging ? 0.90 : 0.35)
        let strokeColor = isDragging
            ? NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
            : NSColor.tertiaryLabelColor.withAlphaComponent(alpha).cgColor

        context.setStrokeColor(strokeColor)
        context.setLineWidth(1.3)
        context.setLineCap(.round)

        let offsets: [CGFloat] = [6, 11, 16]
        for off in offsets {
            let start = CGPoint(x: bounds.maxX - off, y: bounds.minY + 4)
            let end = CGPoint(x: bounds.maxX - 4, y: bounds.minY + off)
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
        }
    }
}

public final class ShelfViewController: NSViewController, CategoryBarDelegate, ShelfGridDelegate {
    internal let categoryBar = CategoryBarView()
    internal let shelfGrid = ShelfGridView()
    private let resizeHandle = ResizeHandleView(frame: .zero)
    private let sidebarSplitter = SidebarSplitterView(frame: .zero)
    private var sidebarWidthConstraint: NSLayoutConstraint?

    private var horizontalConstraints: [NSLayoutConstraint] = []
    private var verticalConstraints: [NSLayoutConstraint] = []

    internal var selectedCategory: Category?

    override public func loadView() {
        let savedW = CGFloat(ConfigManager.shared.config.shelfWidth)
        let savedH = CGFloat(ConfigManager.shared.config.shelfHeight)
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: savedW, height: savedH))
        setupLayout()
    }

    override public func viewWillAppear() {
        super.viewWillAppear()
        snapWindowWidthIfNeeded()
    }

    public func snapWindowWidthIfNeeded() {
        guard let window = self.view.window else { return }
        let config = ConfigManager.shared.config
        let scale = config.shelfIconScale
        let itemWidth: CGFloat = round(82.0 * scale)
        let iconSize = round(48.0 * scale)
        let sideMargin = max(10, round((itemWidth - iconSize) / 2.0))
        let spacingX: CGFloat = 12
        let isVertical = config.categoryOrientation == .vertical
        let sidebarW: CGFloat = isVertical ? 10 + CGFloat(config.sidebarWidth) + 2 + 8 + 8 : 28

        let availableW = max(100, window.frame.width - sidebarW)
        let rawCols = (availableW - sideMargin * 2 + spacingX) / (itemWidth + spacingX)
        let targetCols = max(2, Int(round(rawCols)))
        let gridW = CGFloat(targetCols) * itemWidth + CGFloat(targetCols - 1) * spacingX + sideMargin * 2
        let perfectWidth = min(1400, sidebarW + gridW)

        if abs(window.frame.width - perfectWidth) > 4 {
            let finalFrame = NSRect(x: window.frame.origin.x, y: window.frame.origin.y, width: perfectWidth, height: window.frame.height)
            window.setFrame(finalFrame, display: true, animate: false)
            ConfigManager.shared.updateShelfSize(width: perfectWidth, height: window.frame.height)
        }
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        categoryBar.delegate = self
        shelfGrid.delegate = self
        loadData()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOrientationChanged),
            name: .atoolsCategoryOrientationDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleIconSizeChanged),
            name: .atoolsShelfIconSizeDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFavoritesToggleChanged),
            name: .atoolsFavoritesToggleDidChange,
            object: nil
        )
    }

    override public func viewDidLayout() {
        super.viewDidLayout()
        updateViewTrackingAreas()
    }

    private var trackingArea: NSTrackingArea?
    private var mouseExitWorkItem: DispatchWorkItem?

    private func updateViewTrackingAreas() {
        if let existing = trackingArea { view.removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: view.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(area)
        trackingArea = area
    }

    override public func mouseEntered(with event: NSEvent) {
        mouseExitWorkItem?.cancel()
        mouseExitWorkItem = nil
    }

    override public func mouseExited(with event: NSEvent) {
        guard ConfigManager.shared.config.autoCloseOnMouseExit else { return }
        guard !PanelCoordinator.shared.isShelfPinned else { return }
        if NSApp.modalWindow != nil { return }

        mouseExitWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard ConfigManager.shared.config.autoCloseOnMouseExit else { return }
            guard !PanelCoordinator.shared.isShelfPinned else { return }
            if NSApp.modalWindow != nil { return }
            let mouseLoc = NSEvent.mouseLocation
            if let window = self.view.window, !NSPointInRect(mouseLoc, window.frame) {
                PanelCoordinator.shared.hideAllPanels()
            }
        }
        mouseExitWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    @objc private func handleFavoritesToggleChanged() {
        loadData()
    }

    private func setupLayout() {
        categoryBar.translatesAutoresizingMaskIntoConstraints = false
        sidebarSplitter.translatesAutoresizingMaskIntoConstraints = false
        shelfGrid.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false

        // Sidebar Splitter Callbacks
        sidebarSplitter.onWidthDelta = { [weak self] delta in
            guard let self = self, let constraint = self.sidebarWidthConstraint else { return }
            let currentWidth = constraint.constant
            let newWidth = max(50, min(240, currentWidth + delta))
            constraint.constant = newWidth
            self.view.layoutSubtreeIfNeeded()
        }

        sidebarSplitter.onDragFinished = { [weak self] in
            guard let self = self, let constraint = self.sidebarWidthConstraint else { return }
            ConfigManager.shared.updateSidebarWidth(Double(constraint.constant))
        }

        view.addSubview(categoryBar)
        view.addSubview(sidebarSplitter)
        view.addSubview(shelfGrid)
        view.addSubview(resizeHandle)

        NSLayoutConstraint.activate([
            resizeHandle.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            resizeHandle.widthAnchor.constraint(equalToConstant: 24),
            resizeHandle.heightAnchor.constraint(equalToConstant: 24)
        ])

        // Build Horizontal Constraints
        horizontalConstraints = [
            categoryBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            categoryBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            categoryBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            categoryBar.heightAnchor.constraint(equalToConstant: 34),

            shelfGrid.topAnchor.constraint(equalTo: categoryBar.bottomAnchor, constant: 10),
            shelfGrid.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            shelfGrid.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            shelfGrid.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ]

        // Build Vertical Constraints (with dynamic draggable sidebarSplitter)
        let initialSidebarWidth = CGFloat(ConfigManager.shared.config.sidebarWidth)
        let widthConstraint = categoryBar.widthAnchor.constraint(equalToConstant: initialSidebarWidth)
        sidebarWidthConstraint = widthConstraint

        verticalConstraints = [
            categoryBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            categoryBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            widthConstraint,
            categoryBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),

            sidebarSplitter.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            sidebarSplitter.leadingAnchor.constraint(equalTo: categoryBar.trailingAnchor, constant: 2),
            sidebarSplitter.widthAnchor.constraint(equalToConstant: 8),
            sidebarSplitter.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),

            shelfGrid.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            shelfGrid.leadingAnchor.constraint(equalTo: sidebarSplitter.trailingAnchor, constant: 0),
            shelfGrid.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            shelfGrid.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ]

        let orientation = ConfigManager.shared.config.categoryOrientation
        categoryBar.orientation = orientation
        if orientation == .horizontal {
            sidebarSplitter.isHidden = true
            NSLayoutConstraint.activate(horizontalConstraints)
        } else {
            sidebarSplitter.isHidden = false
            NSLayoutConstraint.activate(verticalConstraints)
        }
    }

    @objc private func handleOrientationChanged() {
        let orientation = ConfigManager.shared.config.categoryOrientation
        categoryBar.orientation = orientation

        NSLayoutConstraint.deactivate(horizontalConstraints)
        NSLayoutConstraint.deactivate(verticalConstraints)

        if orientation == .horizontal {
            sidebarSplitter.isHidden = true
            NSLayoutConstraint.activate(horizontalConstraints)
        } else {
            sidebarSplitter.isHidden = false
            NSLayoutConstraint.activate(verticalConstraints)
        }
        view.layoutSubtreeIfNeeded()
        shelfGrid.reloadData(items: selectedCategory?.items ?? [])
    }

    @objc private func handleIconSizeChanged() {
        if let window = self.view.window {
            let config = ConfigManager.shared.config
            let scale = config.shelfIconScale
            let itemWidth: CGFloat = round(82.0 * scale)
            let iconSize = round(48.0 * scale)
            let sideMargin = max(10, round((itemWidth - iconSize) / 2.0))
            let spacingX: CGFloat = 12
            let isVertical = config.categoryOrientation == .vertical
            let sidebarW: CGFloat = isVertical ? 10 + CGFloat(config.sidebarWidth) + 2 + 8 + 8 : 28

            let availableW = max(100, window.frame.width - sidebarW)
            let currentCols = max(2, Int(round((availableW - sideMargin * 2 + spacingX) / (itemWidth + spacingX))))
            let snappedContentW = CGFloat(currentCols) * itemWidth + CGFloat(currentCols - 1) * spacingX + sideMargin * 2
            let snappedWidth = min(1400, sidebarW + snappedContentW)

            let finalFrame = NSRect(x: window.frame.origin.x, y: window.frame.origin.y, width: snappedWidth, height: window.frame.height)
            window.setFrame(finalFrame, display: true, animate: true)
            ConfigManager.shared.updateShelfSize(width: snappedWidth, height: window.frame.height)
        }
        shelfGrid.reloadData(items: selectedCategory?.items ?? [])
    }

    public func updatePinButtonState(isPinned: Bool) {
        // 兼容保留接口，按钮 UI 已按需求精简移除
    }

    override public func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "," {
            SettingsWindowController.shared.showSettingsWindow()
            return
        }
        super.keyDown(with: event)
    }

    override public func cancelOperation(_ sender: Any?) {
        PanelCoordinator.shared.hideAllPanels()
    }

    public func loadData() {
        var categories = ConfigManager.shared.config.categories
        if !ConfigManager.shared.config.enableFavoritesCategory {
            categories.removeAll(where: { $0.iconSymbol == "star.fill" || $0.name == "常用" })
        }

        if selectedCategory == nil || !categories.contains(where: { $0.id == selectedCategory?.id }) {
            self.selectedCategory = categories.first
        } else if let currentId = selectedCategory?.id {
            self.selectedCategory = categories.first(where: { $0.id == currentId })
        }

        categoryBar.reloadData(categories: categories, selectedId: selectedCategory?.id)
        if let cat = selectedCategory {
            shelfGrid.reloadData(items: cat.items)
            updateStatusBar()
        } else {
            shelfGrid.reloadData(items: [])
            updateStatusBar()
        }
    }

    private func updateStatusBar() {
        // 底层数据状态更新钩子，UI 提示已按需求精简移除
    }

    // MARK: - CategoryBarDelegate
    public func categoryBar(_ bar: CategoryBarView, didSelectCategory category: Category) {
        if let latestCategory = ConfigManager.shared.config.categories.first(where: { $0.id == category.id }) {
            self.selectedCategory = latestCategory
            shelfGrid.reloadData(items: latestCategory.items)
        } else {
            self.selectedCategory = category
            shelfGrid.reloadData(items: category.items)
        }
        updateStatusBar()
    }

    public func categoryBarDidRequestAddCategory(_ bar: CategoryBarView) {
        CategoryInputDialog.prompt(
            title: "新建分类",
            prompt: "请输入新分类的名称：",
            placeholder: "例如：设计、多媒体、常用工具",
            confirmTitle: "创建",
            in: self.view.window
        ) { [weak self] name in
            guard let self = self, let name = name, !name.isEmpty else { return }
            let newCat = ConfigManager.shared.addCategory(name: name)
            self.selectedCategory = newCat
            self.loadData()
        }
    }

    public func categoryBar(_ bar: CategoryBarView, didRequestRenameCategory category: Category) {
        CategoryInputDialog.prompt(
            title: "重命名分类",
            prompt: "请输入「\(category.name)」的新名称：",
            placeholder: "",
            initialValue: category.name,
            confirmTitle: "保存",
            in: self.view.window
        ) { [weak self] newName in
            guard let self = self, let newName = newName, !newName.isEmpty else { return }
            ConfigManager.shared.renameCategory(id: category.id, newName: newName)
            self.loadData()
        }
    }

    public func categoryBar(_ bar: CategoryBarView, didRequestDeleteCategory category: Category) {
        let alert = NSAlert()
        alert.messageText = "删除分类"
        alert.informativeText = "确定要删除分类「\(category.name)」吗？该分类下的 \(category.items.count) 个项目将一并移除。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.window.level = NSWindow.Level(NSWindow.Level.statusBar.rawValue + 1)

        if alert.runModal() == .alertFirstButtonReturn {
            let success = ConfigManager.shared.deleteCategory(id: category.id)
            if success {
                self.selectedCategory = nil
                loadData()
            }
        }
    }

    public func categoryBar(_ bar: CategoryBarView, didMoveCategoryFrom fromIndex: Int, to toIndex: Int) {
        ConfigManager.shared.moveCategory(from: fromIndex, to: toIndex)
        loadData()
    }

    public func categoryBar(_ bar: CategoryBarView, didMoveLauncherItem item: LauncherItem, to category: Category) {
        if ConfigManager.shared.moveItem(id: item.id, toCategoryId: category.id) {
            self.selectedCategory = category
            loadData()
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
    }

    public func categoryBar(_ bar: CategoryBarView, didAddPaths paths: [String], to category: Category) {
        var newItems: [LauncherItem] = []
        for path in paths {
            var name = FileManager.default.displayName(atPath: path)
            if name.hasSuffix(".app") {
                name = (name as NSString).deletingPathExtension
            }
            let isApp = path.hasSuffix(".app")
            let item = LauncherItem(
                name: name,
                itemType: isApp ? .application : .fileOrFolder,
                target: path
            )
            newItems.append(item)
        }

        ConfigManager.shared.addItems(newItems, to: category.id)
        self.selectedCategory = category
        loadData()
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    // MARK: - ShelfGridDelegate
    public func shelfGrid(_ grid: ShelfGridView, didLaunchItem item: LauncherItem) {
        if ConfigManager.shared.config.autoCloseOnLaunch {
            PanelCoordinator.shared.hideAllPanels()
        }
        executeLauncherItem(item)
    }

    public func shelfGrid(_ grid: ShelfGridView, didDeleteItem item: LauncherItem) {
        guard let cat = selectedCategory else { return }
        ConfigManager.shared.removeItem(id: item.id, from: cat.id)
        loadData()
    }

    public func shelfGrid(_ grid: ShelfGridView, didMoveItemFrom fromIndex: Int, to toIndex: Int) {
        guard let cat = selectedCategory else { return }
        ConfigManager.shared.moveItem(from: fromIndex, to: toIndex, in: cat.id)
        loadData()
    }

    public func shelfGrid(_ grid: ShelfGridView, didMoveExternalItemWithID id: UUID, toIndex: Int) {
        guard let cat = selectedCategory else { return }
        if ConfigManager.shared.moveItem(id: id, toCategoryId: cat.id) {
            if let newIdx = ConfigManager.shared.config.categories.first(where: { $0.id == cat.id })?.items.firstIndex(where: { $0.id == id }),
               newIdx != toIndex {
                ConfigManager.shared.moveItem(from: newIdx, to: toIndex, in: cat.id)
            }
            loadData()
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
    }

    public func shelfGrid(_ grid: ShelfGridView, didAddPaths paths: [String]) {
        guard let cat = selectedCategory else { return }
        var newItems: [LauncherItem] = []
        for path in paths {
            var name = FileManager.default.displayName(atPath: path)
            if name.hasSuffix(".app") {
                name = (name as NSString).deletingPathExtension
            }
            let isApp = path.hasSuffix(".app")
            let item = LauncherItem(
                name: name,
                itemType: isApp ? .application : .fileOrFolder,
                target: path
            )
            newItems.append(item)
        }

        ConfigManager.shared.addItems(newItems, to: cat.id)
        loadData()
    }

    private func executeLauncherItem(_ item: LauncherItem) {
        switch item.itemType {
        case .application, .fileOrFolder:
            LauncherExecutor.open(path: item.target)
        case .webURL:
            if let url = URL(string: item.target) {
                NSWorkspace.shared.open(url)
            }
        case .shellScript:
            let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            let task = Process()
            task.launchPath = shell
            task.arguments = ["-c", item.target]
            try? task.run()
        case .appleScript:
            if let script = NSAppleScript(source: item.target) {
                var err: NSDictionary?
                script.executeAndReturnError(&err)
            }
        case .systemAction:
            break
        }
    }
}

public final class ShelfPanel: NSPanel {
    public let shelfViewController = ShelfViewController()

    public init() {
        let savedW = CGFloat(ConfigManager.shared.config.shelfWidth)
        let savedH = CGFloat(ConfigManager.shared.config.shelfHeight)
        let contentRect = NSRect(x: 0, y: 0, width: savedW, height: savedH)
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.minSize = NSSize(width: 240, height: 180)
        self.maxSize = NSSize(width: 1400, height: 900)
        self.isFloatingPanel = true
        self.level = .statusBar
        self.hidesOnDeactivate = false
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true

        let backdrop = VisualEffectBackdropView(frame: contentRect)
        backdrop.autoresizingMask = [.width, .height]
        self.contentView = backdrop

        shelfViewController.view.frame = backdrop.bounds
        shelfViewController.view.autoresizingMask = [.width, .height]
        backdrop.addSubview(shelfViewController.view)

        // Observe resize end to persist window size without I/O thrashing during live drag
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidEndLiveResize(_:)),
            name: NSWindow.didEndLiveResizeNotification,
            object: self
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChanged),
            name: .atoolsThemeDidChange,
            object: nil
        )
        updateWindowAppearanceForTheme()
    }

    @objc private func handleThemeChanged() {
        updateWindowAppearanceForTheme()
    }

    private func updateWindowAppearanceForTheme() {
        let theme = ConfigManager.shared.config.theme
        self.appearance = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
    }

    @objc private func windowDidEndLiveResize(_ notification: Notification) {
        let size = self.frame.size
        ConfigManager.shared.updateShelfSize(width: Double(size.width), height: Double(size.height))
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { false }

    override public func cancelOperation(_ sender: Any?) {
        PanelCoordinator.shared.hideAllPanels()
    }

    override public func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            PanelCoordinator.shared.hideAllPanels()
            return
        }
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "," {
            SettingsWindowController.shared.showSettingsWindow()
            return
        }
        super.keyDown(with: event)
    }

    public func prepareForDisplay() {
        shelfViewController.loadData()
    }
}
