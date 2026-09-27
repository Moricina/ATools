import Foundation
import AppKit

public enum PanelKind {
    case shelf   // 面板 A: Maye Nano 风格分类抽屉
    case search  // 面板 B: Spotlight 风格全盘搜索
}

public enum PanelDismissReason {
    case appDeactivated
    case appSwitched
    case windowResigned
    case outsideClick
}

/// Single source of truth for automatic dismissal. Pinning the shelf always
/// takes precedence over the configured auto-close behavior.
struct PanelDismissPolicy {
    /// Evaluates whether the active panel should be dismissed given current state.
    /// Consolidates all protection conditions: pinned shelf, drag session,
    /// modal windows, settings window key status, and right-click menu protection.
    static func shouldDismiss(
        activePanel: PanelKind,
        isShelfPinned: Bool,
        autoCloseOnDeactivate: Bool,
        isDraggingActive: Bool,
        hasModalWindow: Bool,
        isSettingsWindowKey: Bool = false,
        isRightClickMenuOpen: Bool = false
    ) -> Bool {
        // Drag session, modal windows, right-click menus, and settings window
        // all protect the panel from dismissal.
        guard !isDraggingActive, !hasModalWindow else { return false }
        guard !isRightClickMenuOpen else { return false }
        guard !isSettingsWindowKey else { return false }
        // Pinning the shelf takes precedence over all auto-close behavior.
        if activePanel == .shelf && isShelfPinned { return false }
        return autoCloseOnDeactivate
    }
}

public protocol PanelVisibleFrameProviding: AnyObject {
    /// The visible panel surface in screen coordinates, excluding transparent
    /// window margins used by the reveal animation.
    var visiblePanelFrame: NSRect { get }
}

public final class PanelCoordinator {
    public static let shared = PanelCoordinator()

    private var shelfPanelCreated = false
    private var searchPanelCreated = false

    public private(set) lazy var shelfPanel: ShelfPanel = {
        shelfPanelCreated = true
        return ShelfPanel()
    }()

    public private(set) lazy var searchPanel: SearchPanel = {
        searchPanelCreated = true
        return SearchPanel()
    }()

    /// App that was frontmost before a panel was summoned; it gets keyboard focus back on dismiss.
    private var previousFrontmostApp: NSRunningApplication?

    private var activePanel: PanelKind?
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var workspaceActivationObserver: Any?
    private var windowResignObserver: Any?
    private var panelPresentationGeneration: UInt = 0

    /// 标记当前是否正处于向外部 App 拖拽文件的会话中，拖拽期间屏蔽一切外部失焦销毁
    public var isDraggingActive: Bool = false

    /// Tracks whether a right-click context menu is currently open, so that
    /// the panel is not dismissed when the user right-clicks on a grid item.
    private var isRightClickMenuOpen: Bool = false
    /// Tracks whether a non-left mouse button is currently pressed (prevents
    /// dismissal on right/middle mouseDown; only dismisses on mouseUp).
    private var isNonLeftMouseDown: Bool = false

    // 分类抽屉固定桌面状态，持久化到配置；跨 App 拖拽保护由 isDraggingActive 独立承担
    public var isShelfPinned: Bool {
        get {
            return ConfigManager.shared.config.isShelfPinned
        }
        set {
            guard newValue != ConfigManager.shared.config.isShelfPinned else { return }
            ConfigManager.shared.updateIsShelfPinned(newValue)
            if shelfPanelCreated {
                shelfPanel.shelfViewController.updatePinButtonState(isPinned: newValue)
            }
        }
    }

    private init() {
        // "失焦时自动关闭": also collapse when the user switches apps (⌘Tab, Dock, Mission Control),
        // not only on outside clicks.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleAppResignedActive()
        }

        workspaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if activated?.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
            self.handleAutomaticDismissal(.appSwitched)
        }

        windowResignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let window = notification.object as? NSWindow,
                  window === self.currentPanel else { return }
            // AppKit can briefly resign a panel key while opening a menu or
            // child sheet. Re-check after the current event is dispatched.
            DispatchQueue.main.async {
                self.handleAutomaticDismissal(.windowResigned)
            }
        }

        // Monitor mouse-up events for non-left buttons to track right-click menu state.
        // This catches right-click menus opened on grid items, category pills, etc.
        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isRightClickMenuOpen = true
        }
        NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Delay slightly to avoid a race between menu close and the
            // click event that triggered it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self?.isRightClickMenuOpen = false
            }
        }
    }

    private func handleAppResignedActive() {
        handleAutomaticDismissal(.appDeactivated)
    }

    private var currentPanel: NSPanel? {
        switch activePanel {
        case .shelf: return shelfPanelCreated ? shelfPanel : nil
        case .search: return searchPanelCreated ? searchPanel : nil
        case nil: return nil
        }
    }

    private func handleAutomaticDismissal(_ reason: PanelDismissReason) {
        guard let active = activePanel else { return }
        if reason == .windowResigned {
            // Another ATools-owned window, menu or sheet temporarily taking key
            // status is not an external focus loss. App/workspace notifications
            // cover actual switches to another application.
            if SettingsWindowController.isSettingsWindowKey || NSApp.keyWindow != nil { return }
        }
        guard PanelDismissPolicy.shouldDismiss(
            activePanel: active,
            isShelfPinned: isShelfPinned,
            autoCloseOnDeactivate: ConfigManager.shared.config.autoCloseOnDeactivate,
            isDraggingActive: isDraggingActive,
            hasModalWindow: NSApp.modalWindow != nil,
            isSettingsWindowKey: SettingsWindowController.isSettingsWindowKey,
            isRightClickMenuOpen: isRightClickMenuOpen
        ) else { return }
        hideAllPanels(restoreFocus: false)
    }

    /// 初始化时把面板固定按钮状态同步到当前配置值。
    public func refreshShelfPinState() {
        guard shelfPanelCreated else { return }
        shelfPanel.shelfViewController.updatePinButtonState(isPinned: ConfigManager.shared.config.isShelfPinned)
    }

    public func togglePanel(_ kind: PanelKind) {
        if kind == .shelf && !ConfigManager.shared.config.enableShelfPanel { return }
        if kind == .search && !ConfigManager.shared.config.enableSearchPanel { return }

        if activePanel == kind {
            hideAllPanels()
        } else {
            switchToPanel(kind)
        }
    }

    public func switchToPanel(_ target: PanelKind) {
        runtimeLog("[Panel] switchToPanel(\(target))")
        if target == .shelf && !ConfigManager.shared.config.enableShelfPanel { return }
        if target == .search && !ConfigManager.shared.config.enableSearchPanel { return }

        panelPresentationGeneration &+= 1
        if activePanel == nil,
           let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousFrontmostApp = frontmost
        }

        // 1. Atomically order out any previously active panel (no overlap)
        if let current = activePanel, current != target {
            let panelToHide = (current == .shelf) ? shelfPanel : searchPanel
            panelToHide.orderOut(nil)
            activePanel = nil
        }
        switch target {
        case .shelf:
            // Build content first so the entrance animation isn't stalled by data loading.
            shelfPanel.prepareForDisplay()
            // 鼠标跟随定位 + 多屏可见区域 Clamping
            positionPanelFollowMouse(shelfPanel)
            animatePanelEntrance(shelfPanel)
            NSApp.activate(ignoringOtherApps: true)
            shelfPanel.makeKeyAndOrderFront(nil)
            shelfPanel.orderFrontRegardless()
            // Liquid Glass 的 Metal 活跃着色器依赖窗口在本进程内处于 Key 状态。
            // `.nonactivatingPanel` 保证不抢占其他 App 的前台焦点，这里显式 makeKey()
            // 才能触发真正通透的玻璃材质，避免退回不透明的 inactive 灰底。
            shelfPanel.makeKey()
        case .search:
            AppHotspotIndex.shared.refreshIfStale()
            // Prepare for display (resets to 72pt height) before calculating screen anchor
            searchPanel.prepareForDisplay()
            positionPanelToScreenCenter(searchPanel)
            animatePanelEntrance(searchPanel)
            NSApp.activate(ignoringOtherApps: true)
            searchPanel.makeKeyAndOrderFront(nil)
            searchPanel.orderFrontRegardless()
            searchPanel.makeKey()
        }

        activePanel = target
        installGlobalOutsideClickMonitor()
    }

    /// Liquid-glass entrance: the panel condenses from scale 0.96 with a soft
    /// fade into full clarity, then settles with a gentle rise.
    ///
    /// The scale runs as an explicit Core Animation on the content layer around its centre.
    /// (A view-backed layer's anchorPoint is (0,0), so the previous affine transform grew
    /// the panel out of its bottom-left corner.) The window frame is no longer animated:
    /// NSWindow frame animation is timer-driven and re-lays-out the glass every step.
    private func animatePanelEntrance(_ panel: NSPanel) {
        panel.alphaValue = 0.0
        let duration: CFTimeInterval = 0.26
        let timing = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.0)

        if let layer = panel.contentView?.layer {
            let bounds = layer.bounds
            let center = CATransform3DMakeTranslation(bounds.midX, bounds.midY, 0)
            let scaled = CATransform3DScale(center, 0.96, 0.96, 1)
            let from = CATransform3DTranslate(scaled, -bounds.midX, -bounds.midY + 8, 0)

            let scale = CABasicAnimation(keyPath: "sublayerTransform")
            scale.fromValue = NSValue(caTransform3D: from)
            scale.toValue = NSValue(caTransform3D: CATransform3DIdentity)
            scale.duration = duration
            scale.timingFunction = timing
            layer.add(scale, forKey: "atools.entrance")
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = timing
            panel.animator().alphaValue = 1.0
        }
    }

    /// Reset any transient entrance animation left on a panel's content view.
    private func resetPanelEntrance(_ panel: NSPanel) {
        panel.contentView?.layer?.removeAnimation(forKey: "atools.entrance")
        panel.contentView?.layer?.removeAnimation(forKey: "atools.dismiss")
        panel.alphaValue = 1.0
    }

    /// - Parameter restoreFocus: re-activate the app that was frontmost before the panel was
    ///   summoned. Without this, dismissing with Esc left ATools (a window-less accessory app)
    ///   active and keyboard input went nowhere until the user clicked another window.
    public func hideAllPanels(restoreFocus: Bool = true, animated: Bool = true) {
        panelPresentationGeneration &+= 1
        let generation = panelPresentationGeneration
        let wasShowingPanel = activePanel != nil
        isDraggingActive = false
        stopGlobalOutsideClickMonitor()

        var panelsToHide: [NSPanel] = []
        // Only touch panels that exist; the lazy getters would otherwise build both panels.
        if shelfPanelCreated {
            panelsToHide.append(shelfPanel)
        }
        if searchPanelCreated {
            panelsToHide.append(searchPanel)
        }
        activePanel = nil

        for panel in panelsToHide where panel.isVisible {
            if animated {
                animatePanelDismissal(panel, generation: generation)
            } else {
                panel.orderOut(nil)
                resetPanelEntrance(panel)
            }
        }

        let settingsVisible = SettingsWindowController.isWindowVisible
        if restoreFocus, wasShowingPanel, !settingsVisible, NSApp.isActive,
           let previous = previousFrontmostApp, !previous.isTerminated {
            previous.activate(options: [])
        }
        previousFrontmostApp = nil

        MemoryGuardian.shared.onPanelsDidHide()
    }

    private func animatePanelDismissal(_ panel: NSPanel, generation: UInt) {
        // Do NOT remove the entrance animation before the fade — the sublayerTransform
        // snap-back (0.96→1.0) renders for one frame and causes a visible flash.
        // Clean up after the fade so the panel is already invisible when the layer resets.
        NSAnimationContext.runAnimationGroup(
            { context in
                context.duration = 0.09
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 1.0, 1.0)
                panel.animator().alphaValue = 0.0
            },
            completionHandler: { [weak self, weak panel] in
                guard let self = self, let panel = panel, self.panelPresentationGeneration == generation else { return }
                panel.orderOut(nil)
                self.resetPanelEntrance(panel)
            }
        )
    }

    private func installGlobalOutsideClickMonitor() {
        stopGlobalOutsideClickMonitor()
        // Monitor leftMouseDown globally for outside-click dismissal.
        // Right/middle clicks are tracked separately: we delay dismissal until
        // mouseUp so that right-click context menus can open without closing the panel.
        let globalMask: NSEvent.EventTypeMask = [.leftMouseDown]
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: globalMask) { [weak self] _ in
            self?.handleOutsideInteraction()
        }
        let localMask: NSEvent.EventTypeMask = [.leftMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: localMask) { [weak self] event in
            self?.handleOutsideInteraction()
            return event
        }
    }

    private func stopGlobalOutsideClickMonitor() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        if let monitor = localClickMonitor {
            NSEvent.removeMonitor(monitor)
            localClickMonitor = nil
        }
    }

    private func handleOutsideInteraction() {
        guard activePanel != nil else { return }
        if isDraggingActive || NSApp.modalWindow != nil { return }
        if isRightClickMenuOpen { return }

        let clickLoc = NSEvent.mouseLocation
        if let settingsFrame = SettingsWindowController.visibleWindowFrame, NSPointInRect(clickLoc, settingsFrame) {
            return
        }
        guard let panel = currentPanel else { return }
        // Use the visible content area (excluding transparent margins) to determine
        // whether the click was truly outside the panel. The search panel has 14pt
        // transparent margins around its content for the reveal animation.
        let visibleFrame = (panel as? PanelVisibleFrameProviding)?.visiblePanelFrame ?? panel.frame
        guard !NSPointInRect(clickLoc, visibleFrame) else { return }
        // Delay one RunLoop iteration so that menu opening, drag initiation and
        // other transient states have time to set their flags before we check.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.activePanel != nil else { return }
            if self.isDraggingActive || NSApp.modalWindow != nil { return }
            if self.isRightClickMenuOpen { return }
            self.handleAutomaticDismissal(.outsideClick)
        }
    }

    private func positionPanelFollowMouse(_ panel: NSPanel) {
        let mouseLoc = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { NSMouseInRect(mouseLoc, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        // Two-stage safety clamping: ensure saved panel size fits target screen visibleFrame
        if let screen = activeScreen {
            let visible = screen.visibleFrame
            let maxSafeW = max(240, min(panel.frame.width, visible.width - 32))
            let maxSafeH = max(180, min(panel.frame.height, visible.height - 32))
            if maxSafeW != panel.frame.width || maxSafeH != panel.frame.height {
                panel.setContentSize(NSSize(width: maxSafeW, height: maxSafeH))
            }
        }

        let origin = calculateClampedOrigin(around: mouseLoc, panelSize: panel.frame.size)
        panel.setFrameOrigin(origin)
    }

    private func positionPanelToScreenCenter(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let screen = activeScreen {
            let visible = screen.visibleFrame
            let x = visible.origin.x + (visible.width - panel.frame.width) / 2
            // Anchor search bar top to natural eye level (72% from bottom of visible frame, closer to top)
            let initialTopY = visible.origin.y + (visible.height * 0.72)
            let y = initialTopY - panel.frame.height
            panel.setFrameOrigin(NSPoint(x: x, y: y))

            if let searchPanel = panel as? SearchPanel {
                searchPanel.searchViewController.setInitialScreenAnchor(topY: initialTopY)
            }
        }
    }

    private func calculateClampedOrigin(around mouseLoc: NSPoint, panelSize: NSSize, safeMargin: CGFloat = 8) -> NSPoint {
        let activeScreen = NSScreen.screens.first { NSMouseInRect(mouseLoc, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen = activeScreen else { return mouseLoc }
        let visible = screen.visibleFrame.insetBy(dx: safeMargin, dy: safeMargin)

        // 视线舒适锚点：光标落在抽屉顶部标签栏与网格之间
        var x = mouseLoc.x - (panelSize.width / 2.0)
        var y = mouseLoc.y - (panelSize.height * 0.75)

        // 边界防护 (Clamping)，兼顾主屏、副屏负坐标及系统热角
        let minX = visible.minX
        let maxX = max(minX, visible.maxX - panelSize.width)
        x = min(max(x, minX), maxX)

        let minY = visible.minY
        let maxY = max(minY, visible.maxY - panelSize.height)
        y = min(max(y, minY), maxY)

        return NSPoint(x: x, y: y)
    }
}
