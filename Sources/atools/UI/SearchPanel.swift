import Foundation
import AppKit

public final class FlippedView: NSView {
    override public var isFlipped: Bool { true }

    /// The search panel is borderless and moved by its background. Explicitly
    /// opt into background dragging so clicks on the empty glass area (outside
    /// the search field and results list) always move the window instead of
    /// being swallowed by the hosting view hierarchy.
    override public var mouseDownCanMoveWindow: Bool { true }

    override public func mouseDown(with event: NSEvent) {
        // Some borderless-panel event paths never reach the implicit
        // background-drag handler. If the empty root was hit, start the move
        // directly; controls are still hit-tested first by AppKit.
        window?.performDrag(with: event)
    }
}

public final class SearchViewController: NSViewController, SearchBarDelegate, SearchResultsTableDelegate {
    public static let collapsedHeight: CGFloat = 72
    public static let expandedHeight: CGFloat = 520

    public let searchBar = SearchBarView()
    internal let searchBarOverlayView = NSView()
    public let resultsTable = SearchResultsTableView()
    private let hintsBar = NSTextField(labelWithString: "")

    private var collapsedConstraints: [NSLayoutConstraint] = []
    private var expandedConstraints: [NSLayoutConstraint] = []
    public private(set) var isExpanded: Bool = false
    /// Backdrop reference set by the panel so collapsed state can hide it.
    internal weak var backdropView: VisualEffectBackdropView?

    override public func loadView() {
        let flippedView = FlippedView(frame: NSRect(x: 0, y: 0, width: 680, height: Self.collapsedHeight))
        flippedView.wantsLayer = true
        flippedView.layer?.masksToBounds = true
        self.view = flippedView
        setupLayout()
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        searchBar.delegate = self
        searchBar.textField.customDelegate = self
        resultsTable.delegate = self

        // When the panel becomes key, AppKit may resolve its inherited
        // appearance before the explicit dark window appearance settles. This
        // caused the results to flash with light-mode colors on first render.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, let window = notification.object as? NSWindow, window === self.view.window else { return }
            self.view.layoutSubtreeIfNeeded()
        }

        NotificationCenter.default.addObserver(
            forName: .atoolsThemeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateHintsColor()
        }
    }

    private func updateHintsColor() {
        hintsBar.textColor = GlassPalette.textTertiary(isDark: ConfigManager.shared.config.theme.isDark)
    }

    public func setInitialScreenAnchor(topY: CGFloat) {
        // Kept for compatibility with the panel coordinator; expansion now
        // reads the live capsule frame so moved panels stay aligned.
    }

    private func setupLayout() {
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        resultsTable.translatesAutoresizingMaskIntoConstraints = false
        hintsBar.translatesAutoresizingMaskIntoConstraints = false

        hintsBar.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        updateHintsColor()
        hintsBar.alignment = .right
        hintsBar.stringValue = "⌘C 复制路径   ⌘R 访达显示   ⏎ 打开   Esc 退出"

        // The capsule lives in its own transparent overlay so it can stay
        // visible while the blurred backdrop is faded out when collapsed.
        searchBarOverlayView.wantsLayer = true
        searchBarOverlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBarOverlayView)
        searchBarOverlayView.addSubview(searchBar)

        NSLayoutConstraint.activate([
            searchBarOverlayView.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            searchBarOverlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            searchBarOverlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            searchBarOverlayView.heightAnchor.constraint(equalToConstant: 44),

            searchBar.leadingAnchor.constraint(equalTo: searchBarOverlayView.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: searchBarOverlayView.trailingAnchor),
            searchBar.topAnchor.constraint(equalTo: searchBarOverlayView.topAnchor),
            searchBar.bottomAnchor.constraint(equalTo: searchBarOverlayView.bottomAnchor)
        ])

        view.addSubview(resultsTable)
        view.addSubview(hintsBar)

        collapsedConstraints = [
            searchBarOverlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14)
        ]

        let hintsBottomConstraint = hintsBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -(Self.sheetInset + 8))
        hintsBottomConstraint.priority = NSLayoutConstraint.Priority(999)

        // 展开态约束：仅在展开到 520pt 时激活
        expandedConstraints = [
            // Tight gap: results emerge right under the search text instead of
            // floating in a visibly empty band (10pt looked too airy).
            resultsTable.topAnchor.constraint(equalTo: searchBarOverlayView.bottomAnchor, constant: 2),
            resultsTable.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.sheetInset + 2),
            resultsTable.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -(Self.sheetInset + 2)),
            resultsTable.bottomAnchor.constraint(equalTo: hintsBar.topAnchor, constant: -4),

            hintsBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.sheetInset + 16),
            hintsBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -(Self.sheetInset + 16)),
            hintsBottomConstraint,
            hintsBar.heightAnchor.constraint(equalToConstant: 16)
        ]

        NSLayoutConstraint.activate(collapsedConstraints)
        resultsTable.isHidden = true
        hintsBar.isHidden = true
        resultsTable.alphaValue = 0.0
        hintsBar.alphaValue = 0.0
    }

    public func prepareForDisplay() {
        SearchCoordinator.shared.cancelPendingSearches()
        SpotlightBridge.shared.warmHotFolderCache(maxAge: 5)
        searchBar.text = ""
        resultsTable.updateResults([])
        setPanelExpanded(false, animated: false)
        searchBar.focus()
    }

    /// Incremented on every expand/collapse so stale animation completions are ignored.
    private var transitionGeneration = 0
    private let revealMaskKey = "atools.reveal"
    private let revealRimKey = "atools.reveal.rim"
    /// Geometry shared by the collapsed capsule and the expanded sheet.
    static let sheetInset: CGFloat = 14
    private static let capsuleHeight: CGFloat = 44
    private static let sheetCornerRadius: CGFloat = 20
    private static let expandTiming = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1.0)
    private static let collapseTiming = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 0.2, 1.0)
    private static let expandDuration: CFTimeInterval = 0.30
    private static let collapseDuration: CFTimeInterval = 0.22

    /// 双稳态展开/折叠控制：输入删除至空时平滑淡出结果并收缩窗口，彻底杜绝残影与断续卡顿
    ///
    /// The window is resized only once per transition (to full height before expanding, back to
    /// capsule height after collapsing). The visible motion is a Core Animation mask revealing the
    /// sheet from the top, plus fades on the same timeline. The previous version animated the
    /// NSWindow frame itself: that is timer-driven on the main thread and re-runs Auto Layout and
    /// re-renders the liquid glass on every step, which is why it stuttered.
    public func setPanelExpanded(_ expand: Bool, animated: Bool = true) {
        guard expand != isExpanded || !animated else { return }
        isExpanded = expand
        transitionGeneration &+= 1
        let generation = transitionGeneration

        guard let window = view.window else {
            applyFinalLayout(expanded: expand)
            return
        }

        let topY = window.frame.maxY
        func frame(forHeight height: CGFloat) -> NSRect {
            // Anchor on the window's top edge so the panel never drifts (the capsule sits a fixed
            // 14pt below it in both states).
            return NSRect(x: window.frame.origin.x, y: topY - height, width: window.frame.width, height: height)
        }

        guard animated, window.isVisible, let hostLayer = window.contentView?.layer else {
            removeRevealMask(from: window)
            // Constraints first: the collapsed layout's required constraints pin the window to
            // 72pt, so resizing before swapping them snaps the window straight back.
            applyFinalLayout(expanded: expand)
            window.setFrame(frame(forHeight: expand ? Self.expandedHeight : Self.collapsedHeight), display: true)
            applyFinalLayout(expanded: expand)
            if !expand {
                resultsTable.updateResults([])
            }
            return
        }

        // Where the reveal currently is (mid-animation if we're reversing an in-flight transition).
        let currentVisibleHeight: CGFloat
        if let mask = hostLayer.mask, mask.name == revealMaskKey {
            currentVisibleHeight = (mask.presentation() ?? mask).bounds.height
        } else {
            currentVisibleHeight = Self.capsuleHeight
        }

        if expand {
            // 1. Grow the window in one step while the sheet is still exactly the capsule's rect.
            let fullHeight = Self.expandedHeight
            let width = window.frame.width
            let (mask, rim) = revealLayers(on: hostLayer)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            setSheetHeight(mask, rim, visibleHeight: currentVisibleHeight, windowHeight: fullHeight, width: width)
            CATransaction.commit()

            NSLayoutConstraint.deactivate(collapsedConstraints)
            NSLayoutConstraint.activate(expandedConstraints)
            resultsTable.isHidden = false
            hintsBar.isHidden = false
            if window.frame.height != fullHeight {
                window.setFrame(frame(forHeight: fullHeight), display: false)
            }
            view.layoutSubtreeIfNeeded()

            // 2. Hand the surface over from the capsule to the sheet. Same rect, radius and tint,
            //    so the swap is invisible; then the sheet stretches down from the capsule.
            backdropView?.alphaValue = 1.0
            searchBar.isMergedIntoSheet = true

            animateSheet(mask, rim, toVisibleHeight: fullHeight - Self.sheetInset * 2, windowHeight: fullHeight, width: width,
                         duration: Self.expandDuration, timing: Self.expandTiming)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Self.expandDuration
                ctx.timingFunction = Self.expandTiming
                ctx.allowsImplicitAnimation = true
                resultsTable.animator().alphaValue = 1.0
                hintsBar.animator().alphaValue = 1.0
            }
        } else {
            // Retract the sheet back into the capsule, keeping the expanded layout until it is
            // capsule-sized; then hand the surface back to the capsule and shrink the window.
            let fullHeight = window.frame.height
            let width = window.frame.width
            let hadSheet = hostLayer.mask?.name == revealMaskKey
            let (mask, rim) = revealLayers(on: hostLayer)
            if !hadSheet {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                setSheetHeight(mask, rim, visibleHeight: fullHeight - Self.sheetInset * 2, windowHeight: fullHeight, width: width)
                CATransaction.commit()
            }

            animateSheet(mask, rim, toVisibleHeight: Self.capsuleHeight, windowHeight: fullHeight, width: width,
                         duration: Self.collapseDuration, timing: Self.collapseTiming)
            // The list fades a little faster than the sheet so it's gone before the edge passes it.
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Self.collapseDuration * 0.6
                ctx.timingFunction = Self.collapseTiming
                ctx.allowsImplicitAnimation = true
                resultsTable.animator().alphaValue = 0.0
                hintsBar.animator().alphaValue = 0.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.collapseDuration) { [weak self] in
                guard let self = self, self.transitionGeneration == generation, !self.isExpanded else { return }
                self.applyFinalLayout(expanded: false)
                self.resultsTable.updateResults([])
                window.setFrame(frame(forHeight: Self.collapsedHeight), display: true)
                self.removeRevealMask(from: window)
            }
        }
    }

    private func applyFinalLayout(expanded: Bool) {
        if expanded {
            NSLayoutConstraint.deactivate(collapsedConstraints)
            NSLayoutConstraint.activate(expandedConstraints)
        } else {
            NSLayoutConstraint.deactivate(expandedConstraints)
            NSLayoutConstraint.activate(collapsedConstraints)
        }
        resultsTable.isHidden = !expanded
        hintsBar.isHidden = !expanded
        // Collapsed state leaves the list/hints at 0 so the next reveal fades them in.
        resultsTable.alphaValue = expanded ? 1.0 : 0.0
        hintsBar.alphaValue = expanded ? 1.0 : 0.0
        backdropView?.alphaValue = expanded ? 1.0 : 0.0
        searchBar.isMergedIntoSheet = expanded
        if expanded, let window = view.window, let hostLayer = window.contentView?.layer {
            // The static expanded state is clipped to the capsule-aligned sheet too.
            let (mask, rim) = revealLayers(on: hostLayer)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            setSheetHeight(mask, rim, visibleHeight: window.frame.height - Self.sheetInset * 2,
                           windowHeight: window.frame.height, width: window.frame.width)
            CATransaction.commit()
        }
    }

    /// Mask (what is visible) + rim (hairline outline) for the sheet. Both share the capsule's
    /// horizontal inset and corner radius and hang from the capsule's top edge, so the region
    /// outside the capsule (the old surrounding "ring") is never shown.
    private func revealLayers(on hostLayer: CALayer) -> (CALayer, CALayer) {
        let isDark = ConfigManager.shared.config.theme.isDark
        let mask: CALayer
        if let existing = hostLayer.mask, existing.name == revealMaskKey {
            mask = existing
        } else {
            mask = CALayer()
            mask.name = revealMaskKey
            mask.backgroundColor = NSColor.black.cgColor
            mask.cornerRadius = Self.sheetCornerRadius
            mask.cornerCurve = .continuous
            mask.anchorPoint = CGPoint(x: 0.5, y: 1.0)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hostLayer.mask = mask
            CATransaction.commit()
        }

        let rim: CALayer
        if let existing = hostLayer.sublayers?.first(where: { $0.name == revealRimKey }) {
            rim = existing
        } else {
            rim = CALayer()
            rim.name = revealRimKey
            rim.cornerRadius = Self.sheetCornerRadius
            rim.cornerCurve = .continuous
            rim.borderWidth = 0.75
            rim.anchorPoint = CGPoint(x: 0.5, y: 1.0)
            rim.zPosition = 1000
            hostLayer.addSublayer(rim)
        }
        rim.borderColor = GlassPalette.panelBorder(isDark: isDark).cgColor
        return (mask, rim)
    }

    /// The host layer is not flipped (y = 0 at the bottom): the sheet hangs from the capsule's top edge.
    private func setSheetHeight(_ mask: CALayer, _ rim: CALayer, visibleHeight: CGFloat, windowHeight: CGFloat, width: CGFloat) {
        let bounds = CGRect(x: 0, y: 0, width: width - Self.sheetInset * 2, height: visibleHeight)
        let position = CGPoint(x: width / 2, y: windowHeight - Self.sheetInset)
        for layer in [mask, rim] {
            layer.bounds = bounds
            layer.position = position
        }
    }

    private func animateSheet(_ mask: CALayer, _ rim: CALayer, toVisibleHeight target: CGFloat, windowHeight: CGFloat, width: CGFloat,
                              duration: CFTimeInterval, timing: CAMediaTimingFunction) {
        let source = mask.presentation() ?? mask
        let fromBounds = source.bounds
        let fromPosition = source.position
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        setSheetHeight(mask, rim, visibleHeight: target, windowHeight: windowHeight, width: width)
        CATransaction.commit()

        for layer in [mask, rim] {
            let bounds = CABasicAnimation(keyPath: "bounds")
            bounds.fromValue = NSValue(rect: fromBounds)
            bounds.toValue = NSValue(rect: layer.bounds)
            let position = CABasicAnimation(keyPath: "position")
            position.fromValue = NSValue(point: fromPosition)
            position.toValue = NSValue(point: layer.position)
            let group = CAAnimationGroup()
            group.animations = [bounds, position]
            group.duration = duration
            group.timingFunction = timing
            layer.add(group, forKey: "reveal")
        }
    }

    private func removeRevealMask(from window: NSWindow) {
        guard let hostLayer = window.contentView?.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if hostLayer.mask?.name == revealMaskKey {
            hostLayer.mask = nil
        }
        hostLayer.sublayers?.filter { $0.name == revealRimKey }.forEach { $0.removeFromSuperlayer() }
        CATransaction.commit()
    }

    public func updatePanelHeight(hasResults: Bool, resultCount: Int, animated: Bool = true) {
        setPanelExpanded(hasResults, animated: animated)
    }

    // MARK: - SearchBarDelegate
    public func searchBar(_ searchBar: SearchBarView, didChangeQuery query: String) {
        runtimeLog("[SearchVC] didChangeQuery: '\(query)'")
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // 文字删空立即执行主线程平滑折叠，无需等待后台异步队列回传
            SearchCoordinator.shared.search(query: "") { _ in }
            setPanelExpanded(false, animated: true)
            return
        }

        // 只要有文字输入，立即平滑展开到标准工作区 520pt（若已展开则无任何布局抖动）
        setPanelExpanded(true, animated: true)

        SearchCoordinator.shared.search(query: query) { [weak self] results in
            runtimeLog("[SearchVC] received results count: \(results.count) for query: '\(query)'")
            // 若在搜索计算期间用户已经删空，丢弃过期的结果，防止正在收拢时突发重绘
            guard let self = self, self.isExpanded else { return }
            self.resultsTable.updateResults(results)
        }
    }

    public func searchBarDidPressArrowDown(_ searchBar: SearchBarView) {
        resultsTable.selectNext()
    }

    public func searchBarDidPressArrowUp(_ searchBar: SearchBarView) {
        resultsTable.selectPrevious()
    }

    public func searchBarDidPressEnter(_ searchBar: SearchBarView, isCommandPressed: Bool) {
        resultsTable.executeSelected(isCommandPressed: isCommandPressed)
    }

    public func searchBarDidPressEscape(_ searchBar: SearchBarView) {
        if !searchBar.text.isEmpty {
            searchBar.text = ""
            SearchCoordinator.shared.cancelPendingSearches()
            resultsTable.updateResults([])
            setPanelExpanded(false, animated: true)
        } else {
            PanelCoordinator.shared.hideAllPanels()
        }
    }

    public func searchBarDidPressCopyPath(_ searchBar: SearchBarView) {
        if resultsTable.copySelectedPath() {
            dismissSearchPanel()
        }
    }

    public func searchBarDidPressRevealInFinder(_ searchBar: SearchBarView) {
        if resultsTable.revealSelectedInFinder() {
            dismissSearchPanel()
        }
    }

    private func dismissSearchPanel() {
        PanelCoordinator.shared.hideAllPanels()
        searchBar.text = ""
        resultsTable.updateResults([])
        setPanelExpanded(false, animated: false)
    }

    // MARK: - SearchResultsTableDelegate
    public func searchResultsTable(_ table: SearchResultsTableView, didSelectResult result: SearchResult, isCommandPressed: Bool) {
        dismissSearchPanel()

        if isCommandPressed, let path = result.path {
            let url = URL(fileURLWithPath: path)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else if let action = result.action {
            action()
        } else if let path = result.path {
            LauncherExecutor.open(path: path)
        }
    }

    public func searchResultsTable(_ table: SearchResultsTableView, didCompleteDragResult result: SearchResult) {
        dismissSearchPanel()
    }

    public func searchResultsTableDidRequestDismiss(_ table: SearchResultsTableView) {
        dismissSearchPanel()
    }
}

public final class SearchPanel: NSPanel, PanelVisibleFrameProviding {
    public let searchViewController = SearchViewController()

    public var visiblePanelFrame: NSRect {
        let inset = SearchViewController.sheetInset
        return frame.insetBy(dx: inset, dy: inset)
    }

    public init() {
        let contentRect = NSRect(x: 0, y: 0, width: 680, height: 72)
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isFloatingPanel = true
        self.level = .popUpMenu
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovableByWindowBackground = true
        self.acceptsMouseMovedEvents = true

        // A transparent host holds everything; the blurred backdrop is a
        // sibling below the content so it can fade independently while the
        // search capsule stays visible in collapsed state.
        let hostView = NSView(frame: contentRect)
        hostView.wantsLayer = true
        hostView.autoresizingMask = [.width, .height]
        self.contentView = hostView

        let backdrop = VisualEffectBackdropView(frame: contentRect)
        backdrop.matchesSearchCapsuleAppearance = true
        backdrop.autoresizingMask = [.width, .height]
        hostView.addSubview(backdrop)
        searchViewController.backdropView = backdrop

        searchViewController.view.frame = hostView.bounds
        searchViewController.view.autoresizingMask = [.width, .height]
        hostView.addSubview(searchViewController.view)


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

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { false }

    public func prepareForDisplay() {
        searchViewController.prepareForDisplay()
    }
}
