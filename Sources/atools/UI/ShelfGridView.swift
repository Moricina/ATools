import Foundation
import AppKit

public protocol ShelfGridDelegate: AnyObject {
    func shelfGrid(_ grid: ShelfGridView, didLaunchItem item: LauncherItem)
    func shelfGrid(_ grid: ShelfGridView, didDeleteItem item: LauncherItem)
    func shelfGrid(_ grid: ShelfGridView, didRequestEditItem item: LauncherItem)
    func shelfGrid(_ grid: ShelfGridView, didRequestRelocateItem item: LauncherItem)
    func shelfGridDidRequestCreateItem(_ grid: ShelfGridView)
    func shelfGridDidRequestCleanMissingItems(_ grid: ShelfGridView)
    func shelfGrid(_ grid: ShelfGridView, didAddPaths paths: [String])
    func shelfGrid(_ grid: ShelfGridView, didMoveItemFrom fromIndex: Int, to toIndex: Int)
    func shelfGrid(_ grid: ShelfGridView, didSwapItemAt indexA: Int, with indexB: Int)
    func shelfGrid(_ grid: ShelfGridView, didMoveExternalItemWithID id: UUID, toIndex: Int)
    func shelfGrid(_ grid: ShelfGridView, didSwipeCategoryBy offset: Int)
    func shelfGridDidBeginDrag(_ grid: ShelfGridView)
    func shelfGrid(_ grid: ShelfGridView, didEndDragWith operation: NSDragOperation)
}

public extension ShelfGridDelegate {
    func shelfGrid(_ grid: ShelfGridView, didRequestEditItem item: LauncherItem) {}
    func shelfGrid(_ grid: ShelfGridView, didRequestRelocateItem item: LauncherItem) {}
    func shelfGridDidRequestCreateItem(_ grid: ShelfGridView) {}
    func shelfGridDidRequestCleanMissingItems(_ grid: ShelfGridView) {}
    func shelfGrid(_ grid: ShelfGridView, didSwapItemAt indexA: Int, with indexB: Int) {}
    func shelfGrid(_ grid: ShelfGridView, didSwipeCategoryBy offset: Int) {}
    func shelfGridDidBeginDrag(_ grid: ShelfGridView) {}
    func shelfGrid(_ grid: ShelfGridView, didEndDragWith operation: NSDragOperation) {}
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
    private var longPressWorkItem: DispatchWorkItem?
    private var isLongPressArmed: Bool = false {
        didSet {
            if oldValue != isLongPressArmed {
                updateAppearanceStyles()
            }
        }
    }
    /// 标识当前图标是否正作为拖拽源在网格中充当半透明占位槽
    public var isDraggingSource: Bool = false {
        didSet {
            if oldValue != isDraggingSource {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = window == nil ? 0 : 0.16
                    ctx.allowsImplicitAnimation = true
                    self.animator().alphaValue = isDraggingSource ? 0.22 : 1.0
                }
                updateAppearanceStyles()
            }
        }
    }
    /// Alt/Option 快速交换模式下高亮标记目标交换图标
    public var isSwapTarget: Bool = false {
        didSet {
            if oldValue != isSwapTarget {
                updateAppearanceStyles()
            }
        }
    }
    public var onDragSessionWillBegin: (() -> Void)?
    public var onDragSessionDidEnd: ((NSDragOperation) -> Void)?
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

        let scale: CGFloat
        if isLongPressArmed {
            scale = 1.08
        } else if isSwapTarget {
            scale = 1.05
        } else if isPressed {
            scale = 0.98
        } else if isHovered {
            scale = 1.02
        } else {
            scale = 1.0
        }

        // baseLayer is a standalone CALayer; without an explicit transaction every
        // style change picks up the default 0.25s implicit animation, so hover
        // shadows visibly linger on unselected icons after the mouse moves on.
        CATransaction.begin()
        CATransaction.setAnimationDuration(window == nil ? 0 : 0.10)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))

        let px = physicalOnePixel
        if isSwapTarget {
            liquidBackdrop.isHidden = true
            baseLayer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.26 : 0.18).cgColor
            baseLayer.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
            baseLayer.borderWidth = px * 2.0
            baseLayer.shadowOpacity = 0.22
            baseLayer.shadowRadius = 8
            baseLayer.opacity = 1.0
        } else if isNativeLiquidTheme {
            baseLayer.opacity = 0.0
            if isSelected || isLongPressArmed {
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
            if isSelected || isLongPressArmed {
                baseLayer.backgroundColor = GlassPalette.selectedFill(isDark: isDark).cgColor
                baseLayer.borderColor = GlassPalette.panelBorder(isDark: isDark).cgColor
                baseLayer.borderWidth = px
                baseLayer.shadowOpacity = 0
                baseLayer.opacity = 1.0
            } else if isPressed {
                baseLayer.backgroundColor = GlassPalette.pressedFill(isDark: isDark).cgColor
                baseLayer.borderColor = GlassPalette.panelBorder(isDark: isDark).cgColor
                baseLayer.borderWidth = px
                baseLayer.shadowOpacity = 0
                baseLayer.opacity = 1.0
            } else if isHovered {
                baseLayer.backgroundColor = GlassPalette.controlHoverFill(isDark: isDark).cgColor
                baseLayer.borderColor = GlassPalette.panelBorder(isDark: isDark).cgColor
                baseLayer.borderWidth = px
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

        let textShadow = NSShadow()
        if isDark {
            // 深色模式：无死角黑曜石定向微沉降投影，保持笔画清晰锐利，阻断底层高亮/白色壁纸透光（WCAG 2.1 AA 达标）
            textShadow.shadowColor = NSColor.black.withAlphaComponent(0.68)
            textShadow.shadowOffset = NSSize(width: 0, height: -1.0)
            textShadow.shadowBlurRadius = 1.5
        } else {
            // 浅色模式：超微纯白漫射背光衬底，消除高饱和彩色壁纸/亮色杂色粘连，对比度稳定突破 5.2:1（WCAG 2.1 AA 达标）
            textShadow.shadowColor = NSColor.white.withAlphaComponent(0.65)
            textShadow.shadowOffset = NSSize(width: 0, height: 0.5)
            textShadow.shadowBlurRadius = 1.0
        }
        titleLabel.shadow = textShadow
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
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        isLongPressArmed = false
        isDraggingSource = false
        isSwapTarget = false
        isPressed = false
        isHovered = false
        mouseDownLocation = nil
    }

    override public func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override public func mouseDown(with event: NSEvent) {
        isPressed = true
        isLongPressArmed = false
        mouseDownLocation = event.locationInWindow

        longPressWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.mouseDownLocation != nil else { return }
            self.isLongPressArmed = true
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
        }
        longPressWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    override public func mouseDragged(with event: NSEvent) {
        guard let startPoint = mouseDownLocation else { return }
        let currentPoint = event.locationInWindow
        let dist = hypot(currentPoint.x - startPoint.x, currentPoint.y - startPoint.y)
        let threshold: CGFloat = isLongPressArmed ? 1.0 : 4.5
        if dist > threshold {
            longPressWorkItem?.cancel()
            longPressWorkItem = nil
            mouseDownLocation = nil
            isPressed = false
            isLongPressArmed = false
            startDragSession(with: event)
        }
    }

    override public func mouseUp(with event: NSEvent) {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        isPressed = false
        let wasLongPressArmed = isLongPressArmed
        isLongPressArmed = false
        if mouseDownLocation != nil {
            mouseDownLocation = nil
            if !wasLongPressArmed {
                sendAction(action, to: target)
            }
        }
    }

    override public func rightMouseDown(with event: NSEvent) {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
        isLongPressArmed = false
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
        let liftedFrame = bounds.insetBy(dx: -bounds.width * 0.04, dy: -bounds.height * 0.04)
        dragItem.setDraggingFrame(liftedFrame, contents: snapshot)

        onDragSessionWillBegin?()
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

    public func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        PanelCoordinator.shared.isDraggingActive = true
    }

    public func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        PanelCoordinator.shared.isDraggingActive = false
        onDragSessionDidEnd?(operation)
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
    public static let gridTopMargin: CGFloat = 6
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

    // MARK: - 实时平滑让位、Alt 快速交换、Esc 撤销还原与横向滑动翻页状态
    private var dragSourceID: UUID?
    private var dragSourceIndex: Int?
    private var dragCurrentTargetIndex: Int?
    private var dragOriginalItems: [LauncherItem]?
    private var dragOriginalButtons: [ShelfItemButton]?
    private var crossCategoryGhostButton: ShelfItemButton?
    private var isOptionSwapActive: Bool = false
    private var isDragCancelledByEscape: Bool = false
    private var didCommitCurrentDrag: Bool = false
    private var dragKeyMonitor: Any?
    private var lastKnownDragPointInContent: NSPoint?

    private var horizontalSwipeDelta: CGFloat = 0
    private var hasTriggeredSwipeInGesture: Bool = false

    private let scrollView = ModernScrollView()
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

    deinit {
        removeDragKeyMonitor()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.verticalScroller = KnobOnlyScroller()
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
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
        // 切换分类或重载数据时，立即清理上一分类残留的拖拽快照，防止跨分类切页后旧分类按钮回写重叠
        resetDragPreviewSnapshotBeforeReload()

        let hadItems = !self.items.isEmpty
        self.items = items
        emptyLabel.isHidden = !items.isEmpty

        // 同时从 itemButtons 与 contentView.subviews 收集可复用按钮，确保没有任何孤立子视图残留
        var reusable: [UUID: ShelfItemButton] = [:]
        for sub in contentView.subviews {
            if let btn = sub as? ShelfItemButton {
                reusable[btn.item.id] = btn
            }
        }
        for btn in itemButtons {
            reusable[btn.item.id] = btn
        }

        let scale = ConfigManager.shared.config.shelfIconScale
        var newButtons: [ShelfItemButton] = []
        var reusedAny = false
        for item in items {
            if let existing = reusable[item.id], existing.item == item {
                reusable.removeValue(forKey: item.id)
                if existing.superview !== contentView {
                    contentView.addSubview(existing)
                }
                existing.isDraggingSource = false
                existing.isSwapTarget = false
                existing.alphaValue = 1.0
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

        let keptIdentifiers = Set(newButtons.map { ObjectIdentifier($0) })
        for sub in contentView.subviews {
            if let btn = sub as? ShelfItemButton, !keptIdentifiers.contains(ObjectIdentifier(btn)) {
                btn.removeFromSuperview()
            }
        }
        reusable.values.forEach {
            if !keptIdentifiers.contains(ObjectIdentifier($0)) {
                $0.removeFromSuperview()
            }
        }
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
        btn.onDragSessionWillBegin = { [weak self, weak btn] in
            guard let self = self, let btn = btn else { return }
            self.delegate?.shelfGridDidBeginDrag(self)
            self.beginInternalDragPreview(for: btn)
        }
        btn.onDragSessionDidEnd = { [weak self] operation in
            guard let self = self else { return }
            self.endInternalDragPreview(operation: operation)
            self.delegate?.shelfGrid(self, didEndDragWith: operation)
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

    private func relayoutButtons(animated: Bool, duration: TimeInterval = 0.24) {
        let buttons = visibleButtons
        guard !buttons.isEmpty else {
            contentView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
            return
        }

        let metrics = ShelfGridMetrics(scale: ConfigManager.shared.config.shelfIconScale)
        let itemWidth = metrics.itemWidth
        let itemHeight = metrics.itemWidth
        let sideMargin = metrics.sideMargin
        let topMargin = ShelfGridView.gridTopMargin
        let spacingX = ShelfGridMetrics.spacing
        let spacingY = ShelfGridMetrics.spacing
        let bottomSafePadding: CGFloat = 20

        let availableWidth = max(bounds.width, 100)
        let cols = max(1, Int((availableWidth - sideMargin * 2 + spacingX) / (itemWidth + spacingX)))
        let rows = Int(ceil(Double(buttons.count) / Double(cols)))

        let totalContentHeight = max(bounds.height, CGFloat(rows) * (itemHeight + spacingY) + topMargin + bottomSafePadding)
        contentView.frame = NSRect(x: 0, y: 0, width: availableWidth, height: totalContentHeight)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animated ? duration : 0
            // 阻尼弹簧手感贝塞尔曲线，让位滑入丝滑且无抖动过冲
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
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

    /// 分类切换时的柔和过渡微动画（自适应水平/垂直排版）
    public func playCategoryPageTransition(direction: Int, isVertical: Bool = false) {
        guard direction != 0, window?.isVisible == true else { return }
        let offset: CGFloat = direction > 0 ? 18.0 : -18.0
        let visibleRect = scrollView.documentVisibleRect
        let animatingButtons = itemButtons.filter { btn in
            !btn.isHidden && btn.frame.intersects(visibleRect.insetBy(dx: 0, dy: -40))
        }

        if animatingButtons.isEmpty && !emptyLabel.isHidden {
            emptyLabel.alphaValue = 0.45
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                ctx.allowsImplicitAnimation = true
                emptyLabel.animator().alphaValue = 1.0
            }
            return
        }

        for btn in animatingButtons {
            let finalFrame = btn.frame
            btn.frame = isVertical ? finalFrame.offsetBy(dx: 0, dy: offset) : finalFrame.offsetBy(dx: offset, dy: 0)
            btn.alphaValue = 0.50
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                ctx.allowsImplicitAnimation = true
                btn.animator().frame = finalFrame
                btn.animator().alphaValue = 1.0
            }
        }
    }

    override public func scrollWheel(with event: NSEvent) {
        // 识别触控板双指横向滑动翻页切换分类
        if event.phase == .began {
            horizontalSwipeDelta = 0
            hasTriggeredSwipeInGesture = false
        }

        let absX = abs(event.scrollingDeltaX)
        let absY = abs(event.scrollingDeltaY)
        if (event.phase == .began || event.phase == .changed), absX > absY * 1.35 {
            horizontalSwipeDelta += event.scrollingDeltaX
            if !hasTriggeredSwipeInGesture && abs(horizontalSwipeDelta) >= 42.0 {
                hasTriggeredSwipeInGesture = true
                let offset = horizontalSwipeDelta < 0 ? 1 : -1
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                delegate?.shelfGrid(self, didSwipeCategoryBy: offset)
            }
            return
        }

        if event.phase == .ended || event.phase == .cancelled {
            horizontalSwipeDelta = 0
            hasTriggeredSwipeInGesture = false
        }

        super.scrollWheel(with: event)
    }

    override public func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu(title: "ShelfGridMenu")

        let createItem = NSMenuItem(title: "新建项目...", action: #selector(contextCreateItem), keyEquivalent: "")
        createItem.image = ThumbnailPipeline.shared.symbolIcon(name: "plus.app", pointSize: 13)
        createItem.target = self
        menu.addItem(createItem)

        let missingCount = ConfigManager.shared.scanMissingItems().count
        let cleanTitle = missingCount > 0 ? "一键清理失效项 (\(missingCount))" : "一键清理失效项"
        let cleanItem = NSMenuItem(title: cleanTitle, action: #selector(contextCleanMissingItems), keyEquivalent: "")
        cleanItem.image = ThumbnailPipeline.shared.symbolIcon(name: "trash", pointSize: 13)
        cleanItem.target = self
        menu.addItem(cleanItem)

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

    @objc private func contextCreateItem() {
        delegate?.shelfGridDidRequestCreateItem(self)
    }

    @objc private func contextCleanMissingItems() {
        delegate?.shelfGridDidRequestCleanMissingItems(self)
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

    // MARK: - 实时平滑让位、Alt 快速交换与 Esc 撤销保护引擎

    private func resetDragPreviewSnapshotBeforeReload() {
        if let ghost = crossCategoryGhostButton {
            ghost.removeFromSuperview()
            crossCategoryGhostButton = nil
        }
        dragSourceIndex = nil
        dragCurrentTargetIndex = nil
        dragOriginalItems = nil
        dragOriginalButtons = nil
        lastKnownDragPointInContent = nil
    }

    private func beginInternalDragPreview(for button: ShelfItemButton) {
        guard activeFilter.isEmpty else { return }
        guard let srcIdx = items.firstIndex(where: { $0.id == button.item.id }) else { return }

        if let ghost = crossCategoryGhostButton {
            ghost.removeFromSuperview()
            crossCategoryGhostButton = nil
        }
        dragSourceID = button.item.id
        dragSourceIndex = srcIdx
        dragCurrentTargetIndex = srcIdx
        dragOriginalItems = items
        dragOriginalButtons = itemButtons
        isOptionSwapActive = NSEvent.modifierFlags.contains(.option)
        isDragCancelledByEscape = false
        didCommitCurrentDrag = false
        lastKnownDragPointInContent = nil

        button.isDraggingSource = true
        installDragKeyMonitor()
    }

    /// 跨分类拖入当前网格时，初始化目标分类快照并创建半透明占位图标，让目标分类周围图标同样实时丝滑让位
    private func beginCrossCategoryDragPreview(for externalItem: LauncherItem) {
        guard activeFilter.isEmpty else { return }
        if let oldGhost = crossCategoryGhostButton {
            oldGhost.removeFromSuperview()
        }
        dragSourceID = externalItem.id
        dragSourceIndex = nil
        dragCurrentTargetIndex = nil
        dragOriginalItems = items
        dragOriginalButtons = itemButtons
        isOptionSwapActive = false

        let ghostBtn = makeButton(for: externalItem, scale: ConfigManager.shared.config.shelfIconScale)
        ghostBtn.isDraggingSource = true
        ghostBtn.alphaValue = 0.22
        contentView.addSubview(ghostBtn)
        crossCategoryGhostButton = ghostBtn
        emptyLabel.isHidden = true
        installDragKeyMonitor()
    }

    private func endInternalDragPreview(operation: NSDragOperation) {
        removeDragKeyMonitor()

        for btn in itemButtons {
            btn.isDraggingSource = false
            btn.isSwapTarget = false
            btn.alphaValue = 1.0
        }
        if let origButtons = dragOriginalButtons {
            for btn in origButtons {
                btn.isDraggingSource = false
                btn.isSwapTarget = false
                btn.alphaValue = 1.0
            }
        }

        // 若未在当前网格内落盘提交（例如按 Esc 取消、或拖到面板空白外部松手），平滑回弹还原当前分类至起拖前顺序
        if !didCommitCurrentDrag {
            if let ghost = crossCategoryGhostButton {
                ghost.removeFromSuperview()
                crossCategoryGhostButton = nil
            }
            if let origItems = dragOriginalItems, let origButtons = dragOriginalButtons {
                let currentOrigIDs = Set(origItems.map(\.id))
                let currentGridIDs = Set(items.filter { $0.id != dragSourceID }.map(\.id))
                if currentOrigIDs == currentGridIDs && items != origItems {
                    items = origItems
                    itemButtons = origButtons
                    emptyLabel.isHidden = !origItems.isEmpty
                    relayoutButtons(animated: true, duration: 0.24)
                }
            }
        } else {
            crossCategoryGhostButton = nil
        }

        dragSourceID = nil
        dragSourceIndex = nil
        dragCurrentTargetIndex = nil
        dragOriginalItems = nil
        dragOriginalButtons = nil
        isOptionSwapActive = false
        isDragCancelledByEscape = false
        didCommitCurrentDrag = false
        lastKnownDragPointInContent = nil
    }

    private func installDragKeyMonitor() {
        removeDragKeyMonitor()
        dragKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self, self.dragSourceID != nil else { return event }
            if event.type == .keyDown && event.keyCode == 53 {
                // Esc 键撤销当前拖拽预览：立即将所有图标丝滑回弹至起拖前原位
                self.isDragCancelledByEscape = true
                self.restoreDragPreviewToOriginal(animated: true)
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                return nil
            } else if event.type == .flagsChanged {
                let optionNow = event.modifierFlags.contains(.option)
                if optionNow != self.isOptionSwapActive,
                   !self.isDragCancelledByEscape,
                   self.dragSourceIndex != nil,
                   let targetIdx = self.dragCurrentTargetIndex {
                    self.isOptionSwapActive = optionNow
                    self.applyLiveDragPreview(targetIndex: targetIdx, optionSwap: optionNow)
                }
            }
            return event
        }
    }

    private func removeDragKeyMonitor() {
        if let monitor = dragKeyMonitor {
            NSEvent.removeMonitor(monitor)
            dragKeyMonitor = nil
        }
    }

    private func restoreDragPreviewToOriginal(animated: Bool) {
        guard let origItems = dragOriginalItems, let origButtons = dragOriginalButtons else { return }
        if let ghost = crossCategoryGhostButton {
            ghost.removeFromSuperview()
            crossCategoryGhostButton = nil
        }
        for btn in origButtons {
            btn.isSwapTarget = false
            if btn.superview !== contentView {
                contentView.addSubview(btn)
            }
        }
        items = origItems
        itemButtons = origButtons
        emptyLabel.isHidden = !origItems.isEmpty
        dragCurrentTargetIndex = dragSourceIndex
        relayoutButtons(animated: animated, duration: 0.22)
        if dragSourceIndex == nil {
            // 跨分类预览移出网格后重置快照，以便再次移入时重新生成占位动画
            dragOriginalItems = nil
            dragOriginalButtons = nil
        }
    }

    /// 计算指定网格槽位的矩形坐标
    private func slotFrame(for index: Int) -> NSRect {
        let metrics = ShelfGridMetrics(scale: ConfigManager.shared.config.shelfIconScale)
        let itemWidth = metrics.itemWidth
        let itemHeight = metrics.itemWidth
        let sideMargin = metrics.sideMargin
        let topMargin = ShelfGridView.gridTopMargin
        let spacingX = ShelfGridMetrics.spacing
        let spacingY = ShelfGridMetrics.spacing
        let availableWidth = max(bounds.width, 100)
        let cols = max(1, Int((availableWidth - sideMargin * 2 + spacingX) / (itemWidth + spacingX)))
        let col = max(0, index % cols)
        let row = max(0, index / cols)
        let x = sideMargin + CGFloat(col) * (itemWidth + spacingX)
        let y = topMargin + CGFloat(row) * (itemHeight + spacingY)
        return NSRect(x: x, y: y, width: itemWidth, height: itemHeight)
    }

    /// 根据 contentView 内的坐标计算目标网格槽位索引（含 14% 边界磁滞防抖区，彻底消除边界闪烁）
    private func targetSlotIndex(at contentPoint: NSPoint, itemCount: Int, currentSlot: Int?) -> Int {
        guard itemCount > 0 else { return 0 }
        let metrics = ShelfGridMetrics(scale: ConfigManager.shared.config.shelfIconScale)
        let itemWidth = metrics.itemWidth
        let itemHeight = metrics.itemWidth
        let sideMargin = metrics.sideMargin
        let topMargin = ShelfGridView.gridTopMargin
        let spacingX = ShelfGridMetrics.spacing
        let spacingY = ShelfGridMetrics.spacing

        let availableWidth = max(bounds.width, 100)
        let cols = max(1, Int((availableWidth - sideMargin * 2 + spacingX) / (itemWidth + spacingX)))
        let cellStrideX = itemWidth + spacingX
        let cellStrideY = itemHeight + spacingY

        let rawCol = Int(floor((contentPoint.x - sideMargin + spacingX * 0.5) / cellStrideX))
        let rawRow = Int(floor((contentPoint.y - topMargin + spacingY * 0.5) / cellStrideY))
        let clampedCol = max(0, min(cols - 1, rawCol))
        let clampedRow = max(0, rawRow)
        let candidateSlot = max(0, min(itemCount - 1, clampedRow * cols + clampedCol))

        guard let existingSlot = currentSlot, existingSlot != candidateSlot else {
            return candidateSlot
        }

        // 计算候选槽位中心，要求指针进入槽位核心区（排除最外圈 14% 过渡带）才触发让位切换
        let targetCol = candidateSlot % cols
        let targetRow = candidateSlot / cols
        let slotOriginX = sideMargin + CGFloat(targetCol) * cellStrideX
        let slotOriginY = topMargin + CGFloat(targetRow) * cellStrideY
        let slotRect = NSRect(x: slotOriginX, y: slotOriginY, width: itemWidth, height: itemHeight)
        let coreRect = slotRect.insetBy(dx: itemWidth * 0.14, dy: itemHeight * 0.14)

        // 若指针落在末尾空白区（超出最后一个槽位），允许直接吸附到末尾槽位
        let lastRow = (itemCount - 1) / cols
        let lastCol = (itemCount - 1) % cols
        let lastMaxX = sideMargin + CGFloat(lastCol) * cellStrideX + itemWidth
        let lastMaxY = topMargin + CGFloat(lastRow) * cellStrideY + itemHeight
        if candidateSlot == itemCount - 1 && (contentPoint.y > lastMaxY || (clampedRow == lastRow && contentPoint.x > lastMaxX)) {
            return candidateSlot
        }

        if coreRect.contains(contentPoint) {
            return candidateSlot
        }
        return existingSlot
    }

    private func updateLiveDragReorder(with sender: NSDraggingInfo) {
        guard !isDragCancelledByEscape else { return }
        guard activeFilter.isEmpty else { return }

        let pboard = sender.draggingPasteboard
        let idString = pboard.string(forType: NSPasteboard.PasteboardType(AppConstants.shelfItemReorderType)) ??
                       pboard.string(forType: NSPasteboard.PasteboardType(AppConstants.shelfItemMoveType))
        guard let idString = idString, let sourceId = UUID(uuidString: idString) else { return }

        // 若起拖回调尚未初始化，区分「本分类内重排」与「跨分类拖入」两种情况建立快照
        if dragOriginalItems == nil {
            if let btn = itemButtons.first(where: { $0.item.id == sourceId }) {
                beginInternalDragPreview(for: btn)
            } else if let externalItem = ConfigManager.shared.config.categories.lazy.flatMap(\.items).first(where: { $0.id == sourceId }) {
                beginCrossCategoryDragPreview(for: externalItem)
            }
        }

        guard let origItems = dragOriginalItems else { return }

        let loc = contentView.convert(sender.draggingLocation, from: nil)
        lastKnownDragPointInContent = loc

        // 情况 A：同分类内部实时让位 / Alt 快速交换
        if let sourceIdx = dragSourceIndex, origItems.indices.contains(sourceIdx) {
            let optionNow = NSEvent.modifierFlags.contains(.option)
            let nextSlot = targetSlotIndex(at: loc, itemCount: origItems.count, currentSlot: dragCurrentTargetIndex)

            if nextSlot != dragCurrentTargetIndex || optionNow != isOptionSwapActive {
                dragCurrentTargetIndex = nextSlot
                isOptionSwapActive = optionNow
                applyLiveDragPreview(targetIndex: nextSlot, optionSwap: optionNow)
            }
            return
        }

        // 情况 B：跨分类拖入目标分类网格时的实时插入让位动画
        if let ghostBtn = crossCategoryGhostButton {
            let nextSlot = targetSlotIndex(at: loc, itemCount: origItems.count + 1, currentSlot: dragCurrentTargetIndex)
            if nextSlot != dragCurrentTargetIndex {
                dragCurrentTargetIndex = nextSlot
                applyCrossCategoryLivePreview(targetIndex: nextSlot, ghostButton: ghostBtn)
            }
        }
    }

    private func applyLiveDragPreview(targetIndex: Int, optionSwap: Bool) {
        guard let origItems = dragOriginalItems,
              let origButtons = dragOriginalButtons,
              let sourceIdx = dragSourceIndex,
              origItems.indices.contains(sourceIdx),
              origItems.indices.contains(targetIndex) else { return }

        var newItems = origItems
        var newButtons = origButtons

        for btn in newButtons {
            btn.isSwapTarget = false
        }

        if sourceIdx != targetIndex {
            if optionSwap {
                // Alt/Option 快速交换模式：仅对调源槽位与目标槽位，其余图标静止不动
                newItems.swapAt(sourceIdx, targetIndex)
                newButtons.swapAt(sourceIdx, targetIndex)
                origButtons[targetIndex].isSwapTarget = true
            } else {
                // 默认实时顺移让位模式：取出源图标插入目标槽位，区间内图标顺移一格
                let movedItem = newItems.remove(at: sourceIdx)
                newItems.insert(movedItem, at: targetIndex)
                let movedBtn = newButtons.remove(at: sourceIdx)
                newButtons.insert(movedBtn, at: targetIndex)
            }
        }

        items = newItems
        itemButtons = newButtons
        relayoutButtons(animated: true, duration: 0.24)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    private func applyCrossCategoryLivePreview(targetIndex: Int, ghostButton: ShelfItemButton) {
        guard let origItems = dragOriginalItems,
              let origButtons = dragOriginalButtons else { return }

        let clampedTarget = max(0, min(origItems.count, targetIndex))
        var newItems = origItems
        var newButtons = origButtons

        if ghostButton.superview !== contentView {
            contentView.addSubview(ghostButton)
        }
        // 首次进入目标分类网格时，直接将占位图标定位在目标槽位，避免从 (0,0) 飞入，同时让周围现有图标平滑滑开
        if ghostButton.frame == .zero {
            ghostButton.frame = slotFrame(for: clampedTarget)
        }

        newItems.insert(ghostButton.item, at: clampedTarget)
        newButtons.insert(ghostButton, at: clampedTarget)

        items = newItems
        itemButtons = newButtons
        emptyLabel.isHidden = !newItems.isEmpty
        relayoutButtons(animated: true, duration: 0.24)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    // MARK: - Drag and Drop Support
    override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        let isReorder = pboard.types?.contains(NSPasteboard.PasteboardType(AppConstants.shelfItemReorderType)) == true
        let isMove = pboard.types?.contains(NSPasteboard.PasteboardType(AppConstants.shelfItemMoveType)) == true
        if isReorder || isMove {
            updateLiveDragReorder(with: sender)
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
            if isDragCancelledByEscape {
                return []
            }
            updateLiveDragReorder(with: sender)
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
        if dragOriginalItems != nil {
            restoreDragPreviewToOriginal(animated: true)
        }
    }

    override public func draggingEnded(_ sender: NSDraggingInfo) {
        layer?.borderWidth = 0.0
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderWidth = 0.0
        layer?.backgroundColor = NSColor.clear.cgColor

        if isDragCancelledByEscape {
            restoreDragPreviewToOriginal(animated: true)
            return false
        }

        let pboard = sender.draggingPasteboard

        // 1. Internal item reordering or cross-category move into grid
        let idString = pboard.string(forType: NSPasteboard.PasteboardType(AppConstants.shelfItemReorderType)) ??
                       pboard.string(forType: NSPasteboard.PasteboardType(AppConstants.shelfItemMoveType))
        if let idString = idString, let sourceId = UUID(uuidString: idString) {
            let loc = contentView.convert(sender.draggingLocation, from: nil)

            // 情况 A：同分类内部拖拽落盘
            if let origItems = dragOriginalItems,
               let sourceIndex = dragSourceIndex,
               origItems.indices.contains(sourceIndex),
               origItems[sourceIndex].id == sourceId {
                let finalTargetIndex = dragCurrentTargetIndex ?? targetSlotIndex(at: loc, itemCount: origItems.count, currentSlot: nil)
                let useOptionSwap = NSEvent.modifierFlags.contains(.option) || isOptionSwapActive
                didCommitCurrentDrag = true

                for btn in itemButtons {
                    btn.isDraggingSource = false
                    btn.isSwapTarget = false
                    btn.alphaValue = 1.0
                }

                if sourceIndex != finalTargetIndex {
                    if useOptionSwap {
                        delegate?.shelfGrid(self, didSwapItemAt: sourceIndex, with: finalTargetIndex)
                    } else {
                        delegate?.shelfGrid(self, didMoveItemFrom: sourceIndex, to: finalTargetIndex)
                    }
                }
                return true
            }

            // 情况 B：跨分类拖入当前网格指定槽位落盘
            let baseCount = dragOriginalItems?.count ?? items.count
            let targetIndex = dragCurrentTargetIndex ?? targetSlotIndex(at: loc, itemCount: max(1, baseCount + 1), currentSlot: nil)
            didCommitCurrentDrag = true
            if let ghost = crossCategoryGhostButton {
                ghost.isDraggingSource = false
                ghost.alphaValue = 1.0
                crossCategoryGhostButton = nil
            }
            for btn in itemButtons {
                btn.isDraggingSource = false
                btn.isSwapTarget = false
                btn.alphaValue = 1.0
            }
            delegate?.shelfGrid(self, didMoveExternalItemWithID: sourceId, toIndex: min(targetIndex, baseCount))
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
