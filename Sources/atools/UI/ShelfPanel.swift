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
        let isDark = glassIsDark
        if isAccentActive {
            layer?.backgroundColor = GlassPalette.accentFill(isDark: isDark).cgColor
            layer?.borderColor = GlassPalette.panelBorder(isDark: isDark).cgColor
            layer?.borderWidth = 0.75
            contentTintColor = GlassPalette.accentText(isDark: isDark)
        } else if isHovered {
            layer?.backgroundColor = GlassPalette.controlHoverFill(isDark: isDark).cgColor
            layer?.borderColor = GlassPalette.panelBorder(isDark: isDark).cgColor
            layer?.borderWidth = 0.75
            contentTintColor = isNativeLiquidTheme ? (isDark ? .white : GlassPalette.textPrimary(isDark: false)) : .labelColor
        } else {
            layer?.backgroundColor = isDark
                ? NSColor(white: 1.0, alpha: 0.06).cgColor
                : NSColor(white: 0.0, alpha: 0.04).cgColor
            layer?.borderColor = isDark
                ? NSColor(white: 1.0, alpha: 0.10).cgColor
                : NSColor(white: 0.0, alpha: 0.06).cgColor
            layer?.borderWidth = 0.5
            contentTintColor = isNativeLiquidTheme ? (isDark ? NSColor(white: 1.0, alpha: 0.80) : GlassPalette.textSecondary(isDark: false)) : .secondaryLabelColor
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
        let alpha: CGFloat = isDragging ? 0.48 : (isHovered ? 0.30 : 0.14)
        let lineColor = glassIsDark ? NSColor.white : NSColor.black
        context.setStrokeColor(lineColor.withAlphaComponent(alpha).cgColor)
        context.setLineWidth(1.0)
        context.move(to: CGPoint(x: bounds.midX, y: bounds.minY + 6))
        context.addLine(to: CGPoint(x: bounds.midX, y: bounds.maxY - 6))
        context.strokePath()
    }
}

public final class ResizeHandleView: NSView {
    // Crucial: prevent isMovableByWindowBackground from hijacking mouse drag events
    override public var mouseDownCanMoveWindow: Bool { false }

    private static var diagonalCursor: NSCursor = {
        // Bottom-right corner handle resizes along the NW–SE diagonal.
        let sel = NSSelectorFromString("_windowResizeNorthWestSouthEastCursor")
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
        let minWidth = ShelfGridMetrics.minimumWindowWidth(config: ConfigManager.shared.config)

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
            let snappedWidth = ShelfGridMetrics.snappedWindowWidth(currentWidth: window.frame.width, config: ConfigManager.shared.config)

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
        let strokeColor = NSColor.tertiaryLabelColor.withAlphaComponent(alpha).cgColor

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

/// Root view for the shelf content. The panel is borderless, so the empty
/// glass margins must be able to start a window drag. Interactive children
/// (pills, grid items, splitter, resize handle) each opt out explicitly.
private final class ShelfRootView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    var onMouseActivity: (() -> Void)?
    private var rootTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 24
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = 24
        layer?.masksToBounds = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = rootTrackingArea {
            removeTrackingArea(existing)
        }
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]
        if let window = self.window, NSPointInRect(NSEvent.mouseLocation, window.frame) {
            options.insert(.assumeInside)
        }
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        rootTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onMouseActivity?()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseActivity?()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onMouseActivity?()
    }

    override func mouseDown(with event: NSEvent) {
        // Window-background dragging is not always dispatched from layered
        // borderless panels. Start the move explicitly when this root itself is
        // hit; interactive subviews still receive their own events first.
        window?.performDrag(with: event)
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
    private var dragSessionOriginCategoryId: UUID?
    private var typeAheadQuery = ""
    private var typeAheadResetWorkItem: DispatchWorkItem?

    override public func loadView() {
        let savedW = CGFloat(ConfigManager.shared.config.shelfWidth)
        let savedH = CGFloat(ConfigManager.shared.config.shelfHeight)
        let rootView = ShelfRootView(frame: NSRect(x: 0, y: 0, width: savedW, height: savedH))
        rootView.onMouseActivity = { [weak self] in
            self?.evaluateMouseExitState()
        }
        self.view = rootView
        setupLayout()
    }

    override public func viewWillAppear() {
        super.viewWillAppear()
        snapWindowWidthIfNeeded()
    }

    override public func viewDidAppear() {
        super.viewDidAppear()
        if mouseExitPollTimer == nil {
            beginMouseExitMonitoringOnShow(summonedDirectly: false)
        }
    }

    public func snapWindowWidthIfNeeded() {
        guard let window = self.view.window else { return }
        let perfectWidth = ShelfGridMetrics.snappedWindowWidth(currentWidth: window.frame.width, config: ConfigManager.shared.config)

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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShelfDataChanged),
            name: .atoolsShelfDataDidChange,
            object: nil
        )
    }

    override public func viewDidLayout() {
        super.viewDidLayout()
        updateViewTrackingAreas()
    }

    private var trackingArea: NSTrackingArea?
    private var mouseExitWorkItem: DispatchWorkItem?
    private var mouseExitPollTimer: Timer?
    private var localMouseMoveMonitor: Any?
    private var globalMouseMoveMonitor: Any?
    private var hasMouseEnteredPanel: Bool = false

    public func cancelPendingMouseExitAutoClose() {
        mouseExitWorkItem?.cancel()
        mouseExitWorkItem = nil
    }

    public func beginMouseExitMonitoringOnShow(summonedDirectly: Bool = false) {
        mouseExitWorkItem?.cancel()
        mouseExitWorkItem = nil
        if let window = self.view.window {
            window.acceptsMouseMovedEvents = true
            let mouseLoc = NSEvent.mouseLocation
            let insideShelf = NSPointInRect(mouseLoc, window.frame)
            let insideSettings = SettingsWindowController.visibleWindowFrame.map { NSPointInRect(mouseLoc, $0) } ?? false
            hasMouseEnteredPanel = insideShelf || (summonedDirectly && !insideSettings)
        } else {
            hasMouseEnteredPanel = summonedDirectly
        }
        updateViewTrackingAreas()

        mouseExitPollTimer?.invalidate()
        let timer = Timer(timeInterval: 0.10, target: self, selector: #selector(pollMouseExitState), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        mouseExitPollTimer = timer

        installMouseMoveMonitors()
    }

    public func stopMouseExitMonitoring() {
        mouseExitPollTimer?.invalidate()
        mouseExitPollTimer = nil
        removeMouseMoveMonitors()
        mouseExitWorkItem?.cancel()
        mouseExitWorkItem = nil
        hasMouseEnteredPanel = false
    }

    private func installMouseMoveMonitors() {
        removeMouseMoveMonitors()
        localMouseMoveMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .mouseEntered, .mouseExited, .leftMouseUp, .rightMouseUp]
        ) { [weak self] event in
            self?.evaluateMouseExitState()
            return event
        }
        globalMouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseUp, .rightMouseUp]
        ) { [weak self] _ in
            self?.evaluateMouseExitState()
        }
    }

    private func removeMouseMoveMonitors() {
        if let local = localMouseMoveMonitor {
            NSEvent.removeMonitor(local)
            localMouseMoveMonitor = nil
        }
        if let global = globalMouseMoveMonitor {
            NSEvent.removeMonitor(global)
            globalMouseMoveMonitor = nil
        }
    }

    private func updateViewTrackingAreas() {
        if let existing = trackingArea { view.removeTrackingArea(existing) }
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]
        if let window = view.window, NSPointInRect(NSEvent.mouseLocation, window.frame) {
            options.insert(.assumeInside)
            hasMouseEnteredPanel = true
        }
        let area = NSTrackingArea(
            rect: view.bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        view.addTrackingArea(area)
        trackingArea = area
    }

    override public func mouseEntered(with event: NSEvent) {
        hasMouseEnteredPanel = true
        mouseExitWorkItem?.cancel()
        mouseExitWorkItem = nil
    }

    override public func mouseExited(with event: NSEvent) {
        evaluateMouseExitState()
    }

    @objc private func pollMouseExitState() {
        evaluateMouseExitState()
    }

    private func evaluateMouseExitState() {
        guard let window = self.view.window, window.isVisible else {
            stopMouseExitMonitoring()
            return
        }
        // 固定在桌面时，绝对不受「移出面板自动关闭」影响
        guard !PanelCoordinator.shared.isShelfPinned else {
            mouseExitWorkItem?.cancel()
            mouseExitWorkItem = nil
            return
        }
        guard ConfigManager.shared.config.autoCloseOnMouseExit else {
            mouseExitWorkItem?.cancel()
            mouseExitWorkItem = nil
            return
        }
        if PanelCoordinator.shared.isDraggingActive
            || NSEvent.pressedMouseButtons != 0
            || NSApp.modalWindow != nil
            || PanelCoordinator.shared.isModalDialogOpen
            || PanelCoordinator.shared.isEffectiveMenuOpen {
            mouseExitWorkItem?.cancel()
            mouseExitWorkItem = nil
            return
        }

        let mouseLoc = NSEvent.mouseLocation
        let isInside = NSPointInRect(mouseLoc, window.frame.insetBy(dx: -1, dy: -1))
        if isInside {
            hasMouseEnteredPanel = true
            mouseExitWorkItem?.cancel()
            mouseExitWorkItem = nil
        } else if hasMouseEnteredPanel && mouseExitWorkItem == nil {
            scheduleMouseExitAutoCloseIfNeeded()
        }
    }

    private func scheduleMouseExitAutoCloseIfNeeded() {
        guard ConfigManager.shared.config.autoCloseOnMouseExit else { return }
        guard !PanelCoordinator.shared.isShelfPinned else { return }
        guard !PanelCoordinator.shared.isDraggingActive, NSEvent.pressedMouseButtons == 0 else { return }
        if NSApp.modalWindow != nil || PanelCoordinator.shared.isModalDialogOpen || PanelCoordinator.shared.isEffectiveMenuOpen { return }

        mouseExitWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.mouseExitWorkItem = nil
            guard ConfigManager.shared.config.autoCloseOnMouseExit else { return }
            guard !PanelCoordinator.shared.isShelfPinned else { return }
            guard !PanelCoordinator.shared.isDraggingActive, NSEvent.pressedMouseButtons == 0 else { return }
            if NSApp.modalWindow != nil || PanelCoordinator.shared.isModalDialogOpen || PanelCoordinator.shared.isEffectiveMenuOpen { return }
            let mouseLoc = NSEvent.mouseLocation
            if let window = self.view.window, window.isVisible, !NSPointInRect(mouseLoc, window.frame) {
                PanelCoordinator.shared.hideShelfPanel()
            }
        }
        mouseExitWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    @objc private func handleFavoritesToggleChanged() {
        loadData()
    }

    @objc private func handleShelfDataChanged() {
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
            self.snapWindowWidthIfNeeded()
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
            categoryBar.heightAnchor.constraint(equalToConstant: 36),

            shelfGrid.topAnchor.constraint(equalTo: categoryBar.bottomAnchor, constant: 8),
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
        snapWindowWidthIfNeeded()
        shelfGrid.reloadData(items: selectedCategory?.items ?? [])
    }

    @objc private func handleIconSizeChanged() {
        if let window = self.view.window {
            let snappedWidth = ShelfGridMetrics.snappedWindowWidth(currentWidth: window.frame.width, config: ConfigManager.shared.config)

            let finalFrame = NSRect(x: window.frame.origin.x, y: window.frame.origin.y, width: snappedWidth, height: window.frame.height)
            if finalFrame != window.frame {
                // `animate: true` runs a blocking modal animation; skip it while the shelf is hidden
                // (the settings slider changes this while the panel is ordered out).
                window.setFrame(finalFrame, display: true, animate: window.isVisible)
                ConfigManager.shared.updateShelfSize(width: snappedWidth, height: window.frame.height)
            }
        }
        shelfGrid.reloadData(items: selectedCategory?.items ?? [])
    }

    public func updatePinButtonState(isPinned: Bool) {
        // 兼容保留接口，按钮 UI 已按需求精简移除
    }

    public func handleKeyDown(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            if event.charactersIgnoringModifiers == "," {
                SettingsWindowController.shared.showSettingsWindow()
                return true
            }
            if let chars = event.charactersIgnoringModifiers {
                switch chars {
                case "\u{f702}": // left arrow
                    return categoryBar.moveSelection(by: -1)
                case "\u{f703}": // right arrow
                    return categoryBar.moveSelection(by: 1)
                case "\u{f700}", "\u{f701}": // up/down arrows
                    return categoryBar.moveSelection(by: chars == "\u{f700}" ? -1 : 1)
                default:
                    break
                }
            }
        }

        switch event.keyCode {
        case 123: // left
            return shelfGrid.moveKeyboardSelection(horizontal: -1, vertical: 0)
        case 124: // right
            return shelfGrid.moveKeyboardSelection(horizontal: 1, vertical: 0)
        case 125: // down
            return shelfGrid.moveKeyboardSelection(horizontal: 0, vertical: 1)
        case 126: // up
            return shelfGrid.moveKeyboardSelection(horizontal: 0, vertical: -1)
        case 36, 76: // return / keypad enter
            if shelfGrid.keyboardSelectedItem != nil {
                shelfGrid.executeKeyboardSelection()
                return true
            }
            return false
        case 48: // tab
            return categoryBar.moveSelection(by: event.modifierFlags.contains(.shift) ? -1 : 1)
        case 51, 117: // delete / forward delete
            if !typeAheadQuery.isEmpty {
                if event.keyCode == 51 { typeAheadQuery.removeLast() }
                else { typeAheadQuery.removeAll() }
                applyTypeAhead()
                return true
            }
            return false
        default:
            break
        }

        guard !event.modifierFlags.contains([.command, .control, .option]),
              let chars = event.characters,
              let scalar = chars.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(scalar) || chars == " " else {
            return false
        }
        typeAheadQuery.append(chars)
        applyTypeAhead()
        return true
    }

    public func cancelKeyboardFilter() -> Bool {
        guard !typeAheadQuery.isEmpty else { return false }
        typeAheadQuery.removeAll()
        applyTypeAhead()
        return true
    }

    public func resetKeyboardState() {
        typeAheadResetWorkItem?.cancel()
        typeAheadResetWorkItem = nil
        typeAheadQuery.removeAll()
        shelfGrid.clearKeyboardSelection()
        shelfGrid.applyFilter("")
    }

    private func applyTypeAhead() {
        shelfGrid.applyFilter(typeAheadQuery)
        if !typeAheadQuery.isEmpty {
            shelfGrid.selectFirstVisibleItem()
        }
        typeAheadResetWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, !self.typeAheadQuery.isEmpty else { return }
            self.typeAheadQuery.removeAll()
            self.applyTypeAhead()
        }
        typeAheadResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    override public func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "," {
            SettingsWindowController.shared.showSettingsWindow()
            return
        }
        super.keyDown(with: event)
    }

    override public func cancelOperation(_ sender: Any?) {
        if !cancelKeyboardFilter() {
            if !PanelCoordinator.shared.isShelfPinned {
                PanelCoordinator.shared.hideShelfPanel()
            }
        }
    }

    public func loadData() {
        var categories = ConfigManager.shared.config.categories
        if !ConfigManager.shared.config.enableFavoritesCategory {
            categories.removeAll(where: { $0.isFavorites })
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
        let prevCategory = self.selectedCategory
        typeAheadQuery.removeAll()
        shelfGrid.applyFilter("")
        let latestCategory = ConfigManager.shared.config.categories.first(where: { $0.id == category.id }) ?? category
        self.selectedCategory = latestCategory
        shelfGrid.reloadData(items: latestCategory.items)

        if let prev = prevCategory, prev.id != latestCategory.id {
            let allCats = ConfigManager.shared.config.categories
            let prevIndex = allCats.firstIndex(where: { $0.id == prev.id }) ?? 0
            let newIndex = allCats.firstIndex(where: { $0.id == latestCategory.id }) ?? 0
            let direction = newIndex >= prevIndex ? 1 : -1
            shelfGrid.playCategoryPageTransition(direction: direction, isVertical: categoryBar.orientation == .vertical)
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

        if alert.runModalAboveFloatingWindows() == .alertFirstButtonReturn {
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
        } else if self.selectedCategory?.id != category.id {
            // 若用户从源分类拖出后悬停切到了其他分类，但最终又拖回源分类胶囊松手，确保界面切回源分类
            self.selectedCategory = category
            loadData()
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
        // P0-2: 若启动项的目标路径已失效，拦截无响应点击并弹出友好重定位/清理引导
        if item.checkTargetMissing() {
            promptMissingItemAction(for: item)
            return
        }
        if ConfigManager.shared.config.autoCloseOnLaunch && !PanelCoordinator.shared.isShelfPinned {
            PanelCoordinator.shared.hideShelfPanel()
        }
        executeLauncherItem(item)
    }

    public func shelfGrid(_ grid: ShelfGridView, didDeleteItem item: LauncherItem) {
        guard let cat = selectedCategory else { return }
        ConfigManager.shared.removeItem(id: item.id, from: cat.id)
        loadData()
    }

    public func shelfGrid(_ grid: ShelfGridView, didRequestEditItem item: LauncherItem) {
        LauncherItemEditorDialog.present(for: item, in: selectedCategory?.id) { [weak self] _ in
            self?.loadData()
        }
    }

    public func shelfGrid(_ grid: ShelfGridView, didRequestRelocateItem item: LauncherItem) {
        promptRelocateItem(item)
    }

    public func shelfGridDidRequestCreateItem(_ grid: ShelfGridView) {
        let targetCatId = selectedCategory?.id ?? ConfigManager.shared.config.categories.first?.id
        LauncherItemEditorDialog.presentCreateNew(in: targetCatId) { [weak self] _ in
            self?.loadData()
        }
    }

    public func shelfGridDidRequestCleanMissingItems(_ grid: ShelfGridView) {
        PanelCoordinator.shared.isModalDialogOpen = true
        defer { PanelCoordinator.shared.isModalDialogOpen = false }

        let missing = ConfigManager.shared.scanMissingItems()
        guard !missing.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "无需清理"
            alert.informativeText = "当前所有分类中的启动项路径均有效，未发现失效项目。"
            alert.runModalAboveFloatingWindows()
            return
        }

        let previewLines = missing.prefix(8).map { "• [\($0.category.name)] \($0.item.name) (\($0.item.target))" }.joined(separator: "\n")
        let moreHint = missing.count > 8 ? "\n…等共 \(missing.count) 个失效项目" : ""

        let alert = NSAlert()
        alert.messageText = "确认一键清理 \(missing.count) 个失效启动项？"
        alert.informativeText = "以下项目因软件卸载或文件移动已失效，清理后将从对应分类中移除并自动回收孤立托管图标：\n\n\(previewLines)\(moreHint)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "立即清理")
        alert.addButton(withTitle: "取消")

        if alert.runModalAboveFloatingWindows() == .alertFirstButtonReturn {
            let removedCount = ConfigManager.shared.removeAllMissingItems()
            loadData()
            let done = NSAlert()
            done.messageText = "清理完成"
            done.informativeText = "已成功清理 \(removedCount) 个失效启动项，并已自动回收孤立托管图标。"
            done.alertStyle = .informational
            done.runModalAboveFloatingWindows()
        }
    }

    private func promptMissingItemAction(for item: LauncherItem) {
        PanelCoordinator.shared.isModalDialogOpen = true
        defer { PanelCoordinator.shared.isModalDialogOpen = false }

        let alert = NSAlert()
        alert.messageText = "启动项「\(item.name)」的目标已失效"
        alert.informativeText = "未找到目标路径：\n\(item.target)\n\n该软件或文件可能已被移动、重命名或卸载。您可以立即重新定位目标（保留原有名称、图标、排序与别名），或将其从当前分类中移除。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "重新定位目标...")
        alert.addButton(withTitle: "从分类中移除")
        alert.addButton(withTitle: "取消")

        let response = alert.runModalAboveFloatingWindows()
        if response == .alertFirstButtonReturn {
            promptRelocateItem(item)
        } else if response == .alertSecondButtonReturn {
            if let cat = selectedCategory {
                ConfigManager.shared.removeItem(id: item.id, from: cat.id)
                loadData()
            }
        }
    }

    private func promptRelocateItem(_ item: LauncherItem) {
        PanelCoordinator.shared.isModalDialogOpen = true
        defer { PanelCoordinator.shared.isModalDialogOpen = false }

        let panel = NSOpenPanel()
        panel.title = "重新定位「\(item.name)」的目标应用或文件"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 2)

        let parentDir = (item.target as NSString).deletingLastPathComponent
        if FileManager.default.fileExists(atPath: parentDir) {
            panel.directoryURL = URL(fileURLWithPath: parentDir)
        } else {
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        }

        if panel.runModalAboveFloatingWindows() == .OK, let url = panel.url {
            ConfigManager.shared.relocateItem(id: item.id, in: selectedCategory?.id, newTarget: url.path)
            loadData()
        }
    }

    public func shelfGrid(_ grid: ShelfGridView, didMoveItemFrom fromIndex: Int, to toIndex: Int) {
        guard let cat = selectedCategory else { return }
        ConfigManager.shared.moveItem(from: fromIndex, to: toIndex, in: cat.id)
        loadData()
    }

    public func shelfGrid(_ grid: ShelfGridView, didSwapItemAt indexA: Int, with indexB: Int) {
        guard let cat = selectedCategory else { return }
        ConfigManager.shared.swapItems(at: indexA, and: indexB, in: cat.id)
        loadData()
    }

    public func shelfGrid(_ grid: ShelfGridView, didSwipeCategoryBy offset: Int) {
        _ = categoryBar.moveSelection(by: offset)
    }

    public func shelfGridDidBeginDrag(_ grid: ShelfGridView) {
        // 记录拖拽开始时的源分类 ID（在整个会话期间保持唯一锚定，防止多次跨分类悬停后丢失最初源分类）
        dragSessionOriginCategoryId = selectedCategory?.id
    }

    public func shelfGrid(_ grid: ShelfGridView, didEndDragWith operation: NSDragOperation) {
        defer { dragSessionOriginCategoryId = nil }

        // 若拖拽以失败/取消结束（按 Esc 或松开在非受体区域），且当前分类已被悬停切页至其他分类，自动平滑反向切回原分类
        if operation == [], let originId = dragSessionOriginCategoryId, originId != selectedCategory?.id {
            if let originCat = ConfigManager.shared.config.categories.first(where: { $0.id == originId }) {
                let allCats = ConfigManager.shared.config.categories
                let oldIndex = allCats.firstIndex(where: { $0.id == selectedCategory?.id }) ?? 0
                let newIndex = allCats.firstIndex(where: { $0.id == originId }) ?? 0
                let direction = newIndex >= oldIndex ? 1 : -1

                categoryBar.setSelectedCategory(id: originId, animated: true)
                self.selectedCategory = originCat
                shelfGrid.reloadData(items: originCat.items)
                shelfGrid.playCategoryPageTransition(direction: direction, isVertical: categoryBar.orientation == .vertical)
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
            }
        }
    }

    public func shelfGrid(_ grid: ShelfGridView, didMoveExternalItemWithID id: UUID, toIndex: Int) {
        guard let cat = selectedCategory else { return }
        if ConfigManager.shared.moveItem(id: id, toCategoryId: cat.id, at: toIndex) {
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
        LauncherExecutor.open(item: item)
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
        // Liquid Glass 自己会渲染发丝高光与柔和光晕；关闭系统方形阴影，
        // 避免在圆角玻璃周围出现一块矩形黑影（用户反馈的“四个角”）。
        self.hasShadow = false
        self.isMovableByWindowBackground = true

        updateWindowAppearanceForTheme()

        let backdrop = VisualEffectBackdropView(frame: contentRect)
        backdrop.autoresizingMask = [.width, .height]
        self.contentView = backdrop

        shelfViewController.view.frame = backdrop.bounds
        shelfViewController.view.autoresizingMask = [.width, .height]
        backdrop.addSubview(shelfViewController.view)

        updateWindowAppearanceForTheme()

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
    }

    @objc private func handleThemeChanged() {
        updateWindowAppearanceForTheme()
        shelfViewController.loadData()
    }

    private func updateWindowAppearanceForTheme() {
        let theme = ConfigManager.shared.config.theme
        let app = NSAppearance(named: theme.isDark ? .darkAqua : .aqua)
        self.appearance = app
        contentView?.appearance = app
        shelfViewController.view.appearance = app
        shelfViewController.categoryBar.updatePillsAppearance()
    }

    @objc private func windowDidEndLiveResize(_ notification: Notification) {
        let size = self.frame.size
        ConfigManager.shared.updateShelfSize(width: Double(size.width), height: Double(size.height))
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { false }

    override public func cancelOperation(_ sender: Any?) {
        if !shelfViewController.cancelKeyboardFilter() {
            if !PanelCoordinator.shared.isShelfPinned {
                PanelCoordinator.shared.hideShelfPanel()
            }
        }
    }

    override public func keyDown(with event: NSEvent) {
        if shelfViewController.handleKeyDown(event) {
            return
        }
        if event.keyCode == 53 { // Esc
            if !shelfViewController.cancelKeyboardFilter() {
                if !PanelCoordinator.shared.isShelfPinned {
                    PanelCoordinator.shared.hideShelfPanel()
                }
            }
            return
        }
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "," {
            SettingsWindowController.shared.showSettingsWindow()
            return
        }
        super.keyDown(with: event)
    }

    public func prepareForDisplay() {
        updateWindowAppearanceForTheme()
        shelfViewController.snapWindowWidthIfNeeded()
        shelfViewController.resetKeyboardState()
        shelfViewController.loadData()
        shelfViewController.categoryBar.updatePillsAppearance()
        // mouseExited is not guaranteed when the panel hides under the cursor;
        // clear stale hover so no leftover shadow shows on re-show.
        shelfViewController.shelfGrid.resetInteractionStates()
    }
}
