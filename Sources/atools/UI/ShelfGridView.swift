import Foundation
import AppKit

public protocol ShelfGridDelegate: AnyObject {
    func shelfGrid(_ grid: ShelfGridView, didLaunchItem item: LauncherItem)
    func shelfGrid(_ grid: ShelfGridView, didDeleteItem item: LauncherItem)
    func shelfGrid(_ grid: ShelfGridView, didRequestEditItem item: LauncherItem)
    func shelfGrid(_ grid: ShelfGridView, didRequestRelocateItem item: LauncherItem)
    func shelfGrid(_ grid: ShelfGridView, didAddPaths paths: [String])
    func shelfGrid(_ grid: ShelfGridView, didMoveItemFrom fromIndex: Int, to toIndex: Int)
    func shelfGrid(_ grid: ShelfGridView, didMoveExternalItemWithID id: UUID, toIndex: Int)
}

public extension ShelfGridDelegate {
    func shelfGrid(_ grid: ShelfGridView, didRequestEditItem item: LauncherItem) {}
    func shelfGrid(_ grid: ShelfGridView, didRequestRelocateItem item: LauncherItem) {}
}

/// P0-2：失效启动项右上角黄色感叹号微标视图
private final class MissingTargetBadgeView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let circleRect = bounds.insetBy(dx: 1.5, dy: 1.5)
        ctx.saveGState()

        // 柔和投影增强在亮/暗图标上的辨识度
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 2.0, color: NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.setFillColor(NSColor.systemYellow.cgColor)
        ctx.fillEllipse(in: circleRect)
        ctx.restoreGState()

        // 细描边
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.25).cgColor)
        ctx.setLineWidth(0.8)
        ctx.strokeEllipse(in: circleRect)

        // 绘制中心深色感叹号 "!"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .heavy),
            .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1.0),
            .paragraphStyle: paragraph
        ]
        let str = NSAttributedString(string: "!", attributes: attrs)
        let size = str.size()
        let textRect = NSRect(
            x: (bounds.width - size.width) / 2.0,
            y: (bounds.height - size.height) / 2.0 - 0.5,
            width: size.width,
            height: size.height
        )
        str.draw(in: textRect)
    }
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
    private let missingBadgeView = MissingTargetBadgeView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
    private var rawIconImage: NSImage?

    /// P0-2：标识当前启动项的目标路径是否已失效（文件被移动或软件已卸载）
    public var isTargetMissing: Bool = false {
        didSet {
            if oldValue != isTargetMissing {
                applyIconAndMissingState()
            }
        }
    }

    private var iconTopConstraint: NSLayoutConstraint?
    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?

    private var trackingArea: NSTrackingArea?
    private var mouseDownLocation: NSPoint?
    /// Called when hover state changes so the parent grid can update keyboard selection.
    public var onHoverChanged: ((Bool) -> Void)?
    private var isHovered: Bool = false {
        didSet {
            if oldValue != isHovered {
                onHoverChanged?(isHovered)
                updateAppearanceStyles()
            }
        }
    }
    private var isPressed: Bool = false {
        didSet {
            if oldValue != isPressed {
                updateAppearanceStyles()
            }
        }
    }
    public var isSelected: Bool = false {
        didSet {
            if oldValue != isSelected {
                setAccessibilitySelected(isSelected)
                updateAppearanceStyles()
            }
        }
    }

    // Soft glass base drawn under the icon for hover/pressed states.
    private let baseLayer = CALayer()
    private let liquidBackdrop = NativeLiquidSelectionBackdrop(cornerRadius: 14)

    override public var mouseDownCanMoveWindow: Bool { false }

    public init(item: LauncherItem, scale: Double = ConfigManager.shared.config.shelfIconScale, frame: NSRect = .zero) {
        self.item = item
        self.scale = scale
        self.isTargetMissing = item.checkTargetMissing()
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
        layer?.cornerRadius = 16
        layer?.masksToBounds = false

        baseLayer.cornerRadius = 14
        baseLayer.opacity = 0.0
        layer?.addSublayer(baseLayer)

        liquidBackdrop.contactShadowEnabled = true
        liquidBackdrop.customShadowRadius = 5.5
        liquidBackdrop.isHidden = true
        addSubview(liquidBackdrop, positioned: .below, relativeTo: iconImageView)

        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        iconImageView.wantsLayer = true
        addSubview(iconImageView)

        missingBadgeView.translatesAutoresizingMaskIntoConstraints = false
        missingBadgeView.isHidden = !isTargetMissing
        addSubview(missingBadgeView)

        let initialFontSize = max(10, min(14, round(11.0 * scale)))
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: initialFontSize, weight: .regular)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.textColor = GlassPalette.textPrimary(isDark: glassIsDark)
        titleLabel.stringValue = item.name
        addSubview(titleLabel)

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

            missingBadgeView.topAnchor.constraint(equalTo: iconImageView.topAnchor, constant: -3),
            missingBadgeView.trailingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 4),
            missingBadgeView.widthAnchor.constraint(equalToConstant: 18),
            missingBadgeView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.topAnchor.constraint(equalTo: iconImageView.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)
        ])

        ThumbnailPipeline.shared.icon(forItem: item) { [weak self] img in
            guard let self = self else { return }
            self.rawIconImage = img
            self.applyIconAndMissingState()
        }

        applyIconAndMissingState()
        updateAppearanceStyles()
    }

    private func applyIconAndMissingState() {
        missingBadgeView.isHidden = !isTargetMissing
        if let raw = rawIconImage {
            if isTargetMissing {
                iconImageView.image = ThumbnailPipeline.shared.grayscaleImage(for: raw)
                iconImageView.alphaValue = 0.52
            } else {
                iconImageView.image = raw
                iconImageView.alphaValue = 1.0
            }
        }
        titleLabel.alphaValue = isTargetMissing ? 0.62 : 1.0
        updateToolTipText()
    }

    private func updateToolTipText() {
        var lines: [String] = []
        if isTargetMissing {
            lines.append("\(item.name) ⚠️ [目标已失效或被移动]")
            lines.append("原路径: \(item.target)")
            lines.append("提示: 右键选择「重新定位目标...」或点击图标修复")
        } else {
            lines.append(item.name)
            lines.append(item.target)
            if let args = item.executionContext?.formattedArgumentsString, !args.isEmpty {
                lines.append("启动参数: \(args)")
            }
            if let wd = item.executionContext?.workingDirectory, !wd.isEmpty {
                lines.append("工作目录: \(wd)")
            }
            if !item.tags.isEmpty {
                lines.append("搜索别名: \(item.formattedTagsString)")
            }
        }
        toolTip = lines.joined(separator: "\n")
    }

    override public func layout() {
        super.layout()
        // baseLayer is a standalone CALayer: without this its frame animates implicitly and
        // lags behind the button during window resizes and grid reflows.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        baseLayer.frame = bounds.insetBy(dx: 4, dy: 0)
        liquidBackdrop.frame = bounds.insetBy(dx: 4, dy: 0)
        CATransaction.commit()
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

    internal func updateAppearanceStyles() {
        let isDark = glassIsDark

        let scale: CGFloat = isPressed ? 0.98 : (isHovered ? 1.02 : 1.0)

        // baseLayer is a standalone CALayer; without an explicit transaction every
        // style change picks up the default 0.25s implicit animation, so hover
        // shadows visibly linger on unselected icons after the mouse moves on.
        CATransaction.begin()
        CATransaction.setAnimationDuration(window == nil ? 0 : 0.10)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))

        if isNativeLiquidTheme {
            baseLayer.opacity = 0.0
            if isSelected {
                liquidBackdrop.isHidden = false
                liquidBackdrop.isDark = isDark
                liquidBackdrop.isSelected = true
                liquidBackdrop.isHovered = false
                liquidBackdrop.isPressed = isPressed
                liquidBackdrop.customShadowOpacity = isDark ? 0.16 : 0.05
                liquidBackdrop.customShadowRadius = 5.5
                liquidBackdrop.updateStyles()
            } else if isHovered {
                liquidBackdrop.isHidden = false
                liquidBackdrop.isDark = isDark
                liquidBackdrop.isSelected = false
                liquidBackdrop.isHovered = true
                liquidBackdrop.isPressed = isPressed
                liquidBackdrop.customShadowOpacity = isDark ? 0.09 : 0.035
                liquidBackdrop.customShadowRadius = 5.0
                liquidBackdrop.updateStyles()
            } else {
                liquidBackdrop.isHidden = true
            }
        } else {
            liquidBackdrop.isHidden = true
            if isSelected {
                baseLayer.backgroundColor = GlassPalette.selectedFill(isDark: isDark).cgColor
                baseLayer.borderColor = GlassPalette.panelBorder(isDark: isDark).cgColor
                baseLayer.borderWidth = 0.75
                baseLayer.shadowOpacity = 0
                baseLayer.opacity = 1.0
            } else if isPressed {
                baseLayer.backgroundColor = GlassPalette.pressedFill(isDark: isDark).cgColor
                baseLayer.borderColor = GlassPalette.panelBorder(isDark: isDark).cgColor
                baseLayer.borderWidth = 0.75
                baseLayer.shadowOpacity = 0
                baseLayer.opacity = 1.0
            } else if isHovered {
                baseLayer.backgroundColor = GlassPalette.controlHoverFill(isDark: isDark).cgColor
                baseLayer.borderColor = GlassPalette.panelBorder(isDark: isDark).cgColor
                baseLayer.borderWidth = 0.75
                baseLayer.shadowColor = GlassPalette.shadowColor(isDark: isDark).cgColor
                baseLayer.shadowOpacity = 0.16
                baseLayer.shadowRadius = 8
                baseLayer.shadowOffset = CGSize(width: 0, height: 3)
                baseLayer.opacity = 1.0
            } else {
                baseLayer.shadowOpacity = 0
                baseLayer.opacity = 0.0
            }
        }
        CATransaction.commit()

        // Icon lift with a soft, non-bouncy ease. The view-backed layer's anchor is its corner,
        // so scale around the icon's centre explicitly; and view-backed layers only animate
        // implicitly inside an NSAnimationContext that allows it (CATransaction alone is ignored).
        let iconBounds = iconImageView.bounds
        var transform = CATransform3DMakeTranslation(iconBounds.midX, iconBounds.midY, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        transform = CATransform3DTranslate(transform, -iconBounds.midX, -iconBounds.midY, 0)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = window == nil ? 0 : 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            iconImageView.layer?.transform = transform
        }

        titleLabel.textColor = GlassPalette.textPrimary(isDark: isDark)
        titleLabel.alphaValue = isTargetMissing ? 0.62 : 1.0
        if isNativeLiquidTheme {
            if isDark {
                let sh = NSShadow()
                sh.shadowColor = NSColor.black.withAlphaComponent(0.70)
                sh.shadowOffset = NSSize(width: 0, height: -1)
                sh.shadowBlurRadius = 2.0
                titleLabel.shadow = sh
            } else {
                titleLabel.shadow = nil
            }
        } else {
            titleLabel.shadow = nil
        }
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAppearanceStyles()
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

    /// Clear hover/press residue. mouseExited is not delivered when the panel is
    /// ordered out with the cursor still over it, so a hidden-then-shown panel
    /// could keep a stale shadow on whichever icon the mouse happened to be on.
    public func resetInteractionState() {
        isPressed = false
        isHovered = false
        mouseDownLocation = nil
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
        } else if hit === superview?.window?.contentView {
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
    private var keyboardSelectedID: UUID?
    /// Selection pinned by explicit input (keyboard arrows / click / type-ahead).
    /// A hover-derived highlight is temporary: it falls back to this when the
    /// mouse leaves the icon, so no shadow lingers after the cursor moves away.
    private var pinnedSelectionID: UUID?
    private var activeFilter = ""
    private var targetValidationGeneration: UInt64 = 0

    private let scrollView = NSScrollView()
    private let contentView = FlippedContentView()
    private let emptyLabel = NSTextField(labelWithString: "拖拽软件、文件或脚本至此处快速添加")

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
        registerForDraggedTypes([
            .fileURL,
            NSPasteboard.PasteboardType(AppConstants.shelfItemReorderType),
            NSPasteboard.PasteboardType(AppConstants.shelfItemMoveType)
        ])
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChanged),
            name: .atoolsThemeDidChange,
            object: nil
        )
        updateAppearanceForTheme()
    }

    private func updateAppearanceForTheme() {
        let isDark = ConfigManager.shared.config.theme.isDark
        let app = NSAppearance(named: isDark ? .darkAqua : .aqua)
        self.appearance = app
        contentView.appearance = app
        scrollView.appearance = app
    }

    @objc private func handleThemeChanged() {
        updateAppearanceForTheme()
        for btn in itemButtons {
            btn.updateAppearanceStyles()
        }
        for sub in contentView.subviews {
            if let btn = sub as? ShelfItemButton {
                btn.updateAppearanceStyles()
            }
        }
    }

    override public func layout() {
        super.layout()
        relayoutButtons(animated: false)
    }

    public func reloadData(items: [LauncherItem]) {
        let hadItems = !self.items.isEmpty
        self.items = items
        emptyLabel.isHidden = !items.isEmpty

        // Reuse existing buttons ONLY when the full LauncherItem (including customIconPath,
        // executionContext, tags, name, target) matches.
        var reusable: [UUID: ShelfItemButton] = [:]
        for btn in itemButtons {
            reusable[btn.item.id] = btn
        }

        let scale = ConfigManager.shared.config.shelfIconScale
        var newButtons: [ShelfItemButton] = []
        var reusedAny = false
        for item in items {
            if let existing = reusable[item.id], existing.item == item {
                reusable.removeValue(forKey: item.id)
                if existing.scale != scale {
                    existing.scale = scale
                }
                existing.updateAppearanceStyles()
                newButtons.append(existing)
                reusedAny = true
            } else {
                let btn = makeButton(for: item, scale: scale)
                contentView.addSubview(btn)
                btn.updateAppearanceStyles()
                newButtons.append(btn)
            }
        }
        reusable.values.forEach { $0.removeFromSuperview() }
        itemButtons = newButtons
        if let selectedID = keyboardSelectedID, !items.contains(where: { $0.id == selectedID }) {
            keyboardSelectedID = nil
        }
        if let pinnedID = pinnedSelectionID, !items.contains(where: { $0.id == pinnedID }) {
            pinnedSelectionID = nil
        }
        applyFilter(activeFilter)

        // P0-2: 后台异步校验所有启动项的目标路径是否存在，防止软件卸载或文件移动后残留旧状态
        validateItemTargetsAsynchronously(for: items)

        guard !items.isEmpty else {
            contentView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
            return
        }

        // Only animate edits within the same category (reorder / delete), not category switches.
        relayoutButtons(animated: hadItems && reusedAny && window?.isVisible == true)
    }

    /// 异步校验当前分类内所有项目的目标路径存活状态（对标 GlassDesk IsTargetMissing）
    public func validateItemTargetsAsynchronously(for currentItems: [LauncherItem]) {
        targetValidationGeneration &+= 1
        let gen = targetValidationGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var missingMap: [UUID: Bool] = [:]
            for item in currentItems {
                missingMap[item.id] = item.checkTargetMissing()
            }
            DispatchQueue.main.async {
                guard let self = self, self.targetValidationGeneration == gen else { return }
                for btn in self.itemButtons {
                    if let isMissing = missingMap[btn.item.id] {
                        btn.isTargetMissing = isMissing
                    }
                }
            }
        }
    }

    public func applyFilter(_ query: String) {
        activeFilter = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for button in itemButtons {
            button.isHidden = !activeFilter.isEmpty && !button.item.matchesFilter(activeFilter)
            button.isSelected = false
        }
        // Keep the current selection only if it is still visible; never fall back
        // to the first item, otherwise every panel show paints a stale selection
        // shadow on icon #1 before the user has interacted.
        if let id = keyboardSelectedID, !visibleButtons.contains(where: { $0.item.id == id }) {
            keyboardSelectedID = nil
        }
        updateKeyboardSelectionVisual()
        emptyLabel.stringValue = activeFilter.isEmpty ? "拖拽软件、文件或脚本至此处快速添加" : "无匹配项目"
        emptyLabel.isHidden = !visibleButtons.isEmpty
        relayoutButtons(animated: false)
    }

    private var visibleButtons: [ShelfItemButton] {
        itemButtons.filter { !$0.isHidden }
    }

    public var keyboardSelectedItem: LauncherItem? {
        guard let id = keyboardSelectedID else { return nil }
        return items.first(where: { $0.id == id })
    }

    @discardableResult
    public func moveKeyboardSelection(horizontal: Int, vertical: Int) -> Bool {
        let buttons = visibleButtons
        guard !buttons.isEmpty else { return false }
        let columns = max(1, currentColumnCount())
        let currentIndex = buttons.firstIndex(where: { $0.item.id == keyboardSelectedID }) ?? -1
        let nextIndex: Int
        if currentIndex < 0 {
            nextIndex = 0
        } else {
            nextIndex = max(0, min(buttons.count - 1, currentIndex + horizontal + vertical * columns))
        }
        guard nextIndex != currentIndex else { return false }
        keyboardSelectedID = buttons[nextIndex].item.id
        pinnedSelectionID = keyboardSelectedID
        updateKeyboardSelectionVisual()
        scrollToKeyboardSelection()
        return true
    }

    public func selectFirstVisibleItem() {
        keyboardSelectedID = visibleButtons.first?.item.id
        pinnedSelectionID = keyboardSelectedID
        updateKeyboardSelectionVisual()
        scrollToKeyboardSelection()
    }

    public func executeKeyboardSelection() {
        guard let id = keyboardSelectedID, let button = itemButtons.first(where: { $0.item.id == id }) else { return }
        if let action = button.action, let target = button.target {
            NSApp.sendAction(action, to: target, from: button)
        }
    }

    /// Reset hover/press visuals on every button (called before the panel is re-shown).
    public func resetInteractionStates() {
        for button in itemButtons {
            button.resetInteractionState()
        }
    }

    /// Drop any selection so the panel re-opens with no default highlight.
    public func clearKeyboardSelection() {
        keyboardSelectedID = nil
        pinnedSelectionID = nil
        updateKeyboardSelectionVisual()
    }

    private func updateKeyboardSelectionVisual() {
        for button in itemButtons {
            button.isSelected = button.item.id == keyboardSelectedID && !button.isHidden
        }
    }

    private func currentColumnCount() -> Int {
        let metrics = ShelfGridMetrics(scale: ConfigManager.shared.config.shelfIconScale)
        let availableWidth = max(bounds.width, 100)
        return max(1, Int((availableWidth - metrics.sideMargin * 2 + ShelfGridMetrics.spacing) / (metrics.itemWidth + ShelfGridMetrics.spacing)))
    }

    private func scrollToKeyboardSelection() {
        guard let id = keyboardSelectedID,
              let button = itemButtons.first(where: { $0.item.id == id }) else { return }
        contentView.layoutSubtreeIfNeeded()
        _ = scrollView.contentView.scrollToVisible(button.frame)
    }

    private func makeButton(for item: LauncherItem, scale: Double) -> ShelfItemButton {
        let btn = ShelfItemButton(item: item, scale: scale, frame: .zero)
        btn.target = self
        btn.action = #selector(itemClicked(_:))
        btn.onHoverChanged = { [weak self, weak btn] isHovered in
            guard let self = self, let btn = btn else { return }
            // Move keyboard selection to the hovered item so the highlight follows the mouse.
            if isHovered {
                if self.keyboardSelectedID != btn.item.id {
                    self.keyboardSelectedID = btn.item.id
                    self.updateKeyboardSelectionVisual()
                }
            } else if self.keyboardSelectedID == btn.item.id {
                // Mouse left the icon (or the panel): restore the pinned selection
                // — nil for hover-only sessions, so the shadow disappears.
                self.keyboardSelectedID = self.pinnedSelectionID
                self.updateKeyboardSelectionVisual()
            }
        }

        // Standard Cocoa context menu using representedObject
        let menu = NSMenu(title: "ShelfItemMenu")

        let openItem = NSMenuItem(title: "打开", action: #selector(contextOpen(_:)), keyEquivalent: "")
        openItem.image = ThumbnailPipeline.shared.symbolIcon(name: "arrow.up.forward.app", pointSize: 13)
        openItem.target = self
        openItem.representedObject = item
        menu.addItem(openItem)

        let editItem = NSMenuItem(title: "编辑项目属性...", action: #selector(contextEditItem(_:)), keyEquivalent: "")
        editItem.image = ThumbnailPipeline.shared.symbolIcon(name: "slider.horizontal.3", pointSize: 13)
        editItem.target = self
        editItem.representedObject = item
        menu.addItem(editItem)

        let relocateItem = NSMenuItem(title: "重新定位目标...", action: #selector(contextRelocateItem(_:)), keyEquivalent: "")
        relocateItem.image = ThumbnailPipeline.shared.symbolIcon(name: "arrow.triangle.2.circlepath", pointSize: 13)
        relocateItem.target = self
        relocateItem.representedObject = item
        menu.addItem(relocateItem)

        let revealItem = NSMenuItem(title: "在访达中显示", action: #selector(contextReveal(_:)), keyEquivalent: "")
        revealItem.image = ThumbnailPipeline.shared.symbolIcon(name: "folder", pointSize: 13)
        revealItem.target = self
        revealItem.representedObject = item
        menu.addItem(revealItem)

        menu.addItem(NSMenuItem.separator())

        let deleteItem = NSMenuItem(title: "从分类中移除", action: #selector(contextDelete(_:)), keyEquivalent: "")
        deleteItem.image = ThumbnailPipeline.shared.symbolIcon(name: "trash", pointSize: 13)
        deleteItem.target = self
        deleteItem.representedObject = item
        menu.addItem(deleteItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "偏好设置...", action: #selector(contextOpenSettings), keyEquivalent: "")
        settingsItem.image = ThumbnailPipeline.shared.symbolIcon(name: "gearshape", pointSize: 13)
        settingsItem.target = self
        menu.addItem(settingsItem)

        btn.menu = menu
        return btn
    }

    private func relayoutButtons(animated: Bool) {
        let buttons = visibleButtons
        guard !buttons.isEmpty else {
            contentView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
            return
        }

        let metrics = ShelfGridMetrics(scale: ConfigManager.shared.config.shelfIconScale)
        let itemWidth = metrics.itemWidth
        let itemHeight = metrics.itemWidth
        let sideMargin = metrics.sideMargin
        let topMargin: CGFloat = 12
        let spacingX = ShelfGridMetrics.spacing
        let spacingY = ShelfGridMetrics.spacing
        let bottomSafePadding: CGFloat = 20

        let availableWidth = max(bounds.width, 100)
        let cols = max(1, Int((availableWidth - sideMargin * 2 + spacingX) / (itemWidth + spacingX)))
        let rows = Int(ceil(Double(buttons.count) / Double(cols)))

        let totalContentHeight = max(bounds.height, CGFloat(rows) * (itemHeight + spacingY) + topMargin + bottomSafePadding)
        contentView.frame = NSRect(x: 0, y: 0, width: availableWidth, height: totalContentHeight)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animated ? 0.22 : 0
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)
            ctx.allowsImplicitAnimation = animated
            for (index, btn) in buttons.enumerated() {
                let col = index % cols
                let row = index / cols
                let x = sideMargin + CGFloat(col) * (itemWidth + spacingX)
                // Flipped coordinates: y starts from top margin
                let y = topMargin + CGFloat(row) * (itemHeight + spacingY)
                let frame = NSRect(x: x, y: y, width: itemWidth, height: itemHeight)

                // New buttons start at their slot; only moved buttons glide.
                if animated && btn.frame != .zero && btn.frame != frame {
                    btn.animator().frame = frame
                } else {
                    btn.frame = frame
                }
            }
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

    @objc private func contextTogglePin() {
        PanelCoordinator.shared.isShelfPinned.toggle()
    }

    @objc private func contextOpenSettings() {
        SettingsWindowController.shared.showSettingsWindow()
    }

    @objc private func contextCloseShelf() {
        PanelCoordinator.shared.hideShelfPanel(forceHidePinned: true)
    }

    @objc private func itemClicked(_ sender: ShelfItemButton) {
        keyboardSelectedID = sender.item.id
        pinnedSelectionID = sender.item.id
        updateKeyboardSelectionVisual()
        delegate?.shelfGrid(self, didLaunchItem: sender.item)
    }

    @objc private func contextOpen(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? LauncherItem else { return }
        delegate?.shelfGrid(self, didLaunchItem: item)
    }

    @objc private func contextEditItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? LauncherItem else { return }
        delegate?.shelfGrid(self, didRequestEditItem: item)
    }

    @objc private func contextRelocateItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? LauncherItem else { return }
        delegate?.shelfGrid(self, didRequestRelocateItem: item)
    }

    @objc private func contextReveal(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? LauncherItem else { return }
        if item.checkTargetMissing() {
            delegate?.shelfGrid(self, didRequestRelocateItem: item)
            return
        }
        NSWorkspace.shared.selectFile(item.target, inFileViewerRootedAtPath: "")
    }

    @objc private func contextDelete(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? LauncherItem else { return }
        delegate?.shelfGrid(self, didDeleteItem: item)
    }

    // MARK: - Drag and Drop Support
    override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        let isReorder = pboard.types?.contains(NSPasteboard.PasteboardType(AppConstants.shelfItemReorderType)) == true
        let isMove = pboard.types?.contains(NSPasteboard.PasteboardType(AppConstants.shelfItemMoveType)) == true
        if isReorder || isMove {
            return .move
        }
        if pboard.types?.contains(.fileURL) == true {
            window?.orderFrontRegardless()
            wantsLayer = true
            layer?.cornerRadius = 14
            layer?.borderWidth = 0.75
            layer?.borderColor = GlassPalette.panelBorder(isDark: glassIsDark).cgColor
            layer?.backgroundColor = GlassPalette.dropTargetFill(isDark: glassIsDark).cgColor
            return .copy
        }
        return []
    }

    override public func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        let isReorder = pboard.types?.contains(NSPasteboard.PasteboardType(AppConstants.shelfItemReorderType)) == true
        let isMove = pboard.types?.contains(NSPasteboard.PasteboardType(AppConstants.shelfItemMoveType)) == true
        if isReorder || isMove {
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

        // 1. Internal item reordering or cross-category move into grid
        let idString = pboard.string(forType: NSPasteboard.PasteboardType(AppConstants.shelfItemReorderType)) ??
                       pboard.string(forType: NSPasteboard.PasteboardType(AppConstants.shelfItemMoveType))
        if let idString = idString, let sourceId = UUID(uuidString: idString) {
            let loc = contentView.convert(sender.draggingLocation, from: nil)
            var targetIndex = items.count - 1

            for (idx, btn) in itemButtons.enumerated() {
                if loc.y < btn.frame.maxY && loc.x < btn.frame.maxX {
                    targetIndex = idx
                    break
                }
            }

            if let sourceIndex = items.firstIndex(where: { $0.id == sourceId }) {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.shelfGrid(self, didMoveItemFrom: sourceIndex, to: targetIndex)
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.shelfGrid(self, didMoveExternalItemWithID: sourceId, toIndex: targetIndex)
                }
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

/// Single source of truth for shelf grid geometry. The same numbers used to be duplicated in
/// four places (grid layout, resize handle, snapping, icon-size change) with chrome widths
/// that didn't match the real constraints, leaving the right margin 4–8pt wider than the left.
public struct ShelfGridMetrics {
    public static let spacing: CGFloat = 12

    public let itemWidth: CGFloat
    public let iconSize: CGFloat
    public let sideMargin: CGFloat

    public init(scale: Double) {
        itemWidth = round(82.0 * scale)
        iconSize = round(48.0 * scale)
        sideMargin = max(10, round((itemWidth - iconSize) / 2.0))
    }

    /// Horizontal window space not occupied by the grid view (must mirror ShelfViewController's constraints).
    public static func chromeWidth(for config: AtoolsConfig) -> CGFloat {
        if config.categoryOrientation == .vertical {
            // bar leading 10 + sidebar + splitter gap 2 + splitter 8 + grid trailing 4
            return 10 + CGFloat(config.sidebarWidth) + 2 + 8 + 4
        }
        // grid leading 10 + trailing 10
        return 20
    }

    /// Window width that fits an exact number of columns with symmetric margins.
    public static func snappedWindowWidth(currentWidth: CGFloat, config: AtoolsConfig, minColumns: Int = 2) -> CGFloat {
        let metrics = ShelfGridMetrics(scale: config.shelfIconScale)
        let chrome = chromeWidth(for: config)
        let availableW = max(100, currentWidth - chrome)
        let rawCols = (availableW - metrics.sideMargin * 2 + spacing) / (metrics.itemWidth + spacing)
        let cols = max(minColumns, Int(round(rawCols)))
        let gridW = CGFloat(cols) * metrics.itemWidth + CGFloat(cols - 1) * spacing + metrics.sideMargin * 2
        return min(1400, chrome + gridW)
    }

    public static func minimumWindowWidth(config: AtoolsConfig) -> CGFloat {
        let metrics = ShelfGridMetrics(scale: config.shelfIconScale)
        let minContentW = 2 * metrics.itemWidth + spacing + metrics.sideMargin * 2
        return max(240, chromeWidth(for: config) + minContentW)
    }
}
