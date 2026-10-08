import Foundation
import AppKit
import ApplicationServices

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

            // 关键保护：若激活的是无 Dock 图标的辅助浮层工具（如剪贴板管理器 AuraSnap、Maccy、系统表情面板等，activationPolicy != .regular），
            // 绝不视为真正的切应用退出，保持全盘搜索面板开启并等待接收其回传粘贴内容！
            if activated?.activationPolicy == .accessory || activated?.activationPolicy == .prohibited {
                runtimeLog("[Panel] workspaceObserver: ignoring activation of accessory tool \(activated?.bundleIdentifier ?? "")")
                return
            }

            // 关键保护：若全盘搜索可见，外部剪贴板工具退场时系统可能短暂将焦点切给原先的后台应用。
            // 检查剪贴板是否在搜索会话期间发生了更新（changeCount 变化）。
            if self.searchPanelCreated && self.searchPanel.isVisible {
                let initialCount = self.searchPanel.summonPasteboardChangeCount
                let currentCount = NSPasteboard.general.changeCount
                if currentCount > initialCount {
                    runtimeLog("[Panel] workspaceObserver: pasteboard changed during search session (\(initialCount) -> \(currentCount)), preserving search panel and bringing to front.")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        if self.searchPanelCreated && self.searchPanel.isVisible {
                            self.searchPanel.makeKeyAndOrderFront(nil)
                            _ = self.searchPanel.searchViewController.searchBar.textField.pasteLatestFromClipboardIfNeeded(since: initialCount)
                        }
                    }
                    return
                }
            }

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
                // 关键保护：全盘搜索面板作为系统级临时输入中心（类似 Spotlight），
                // 绝不因暂时的 windowResigned（如呼出剪贴板历史 AuraSnap、Maccy、系统表情输入、输入法选词等）而自动关闭！
                if self.searchPanelCreated && self.searchPanel.isVisible {
                    runtimeLog("[Panel] windowResign: search panel is open, preserving panel for auxiliary input / clipboard tools.")
                    return
                }
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

    public var isSearchPanelVisible: Bool {
        return searchPanelCreated && searchPanel.isVisible
    }

    private var isAnyPanelShowing: Bool {
        return (shelfPanelCreated && shelfPanel.isVisible) || (searchPanelCreated && searchPanel.isVisible)
    }

    private var currentPanel: NSPanel? {
        if searchPanelCreated && searchPanel.isVisible {
            return searchPanel
        }
        if shelfPanelCreated && shelfPanel.isVisible {
            return shelfPanel
        }
        return nil
    }

    private func recordPreviousFrontmostAppIfNeeded() {
        if previousFrontmostApp == nil,
           let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousFrontmostApp = frontmost
        }
    }

    private func restoreFocusIfNeeded(restoreFocus: Bool) {
        let settingsVisible = SettingsWindowController.isWindowVisible
        if restoreFocus, !settingsVisible, NSApp.isActive,
           let previous = previousFrontmostApp, !previous.isTerminated {
            previous.activate(options: [])
        }
        previousFrontmostApp = nil
    }

    private func handleAutomaticDismissal(_ reason: PanelDismissReason) {
        if reason == .windowResigned {
            // Another ATools-owned window, menu or sheet temporarily taking key
            // status is not an external focus loss. App/workspace notifications
            // cover actual switches to another application.
            if SettingsWindowController.isSettingsWindowKey || NSApp.keyWindow != nil {
                runtimeLog("[Panel] autoDismiss(\(reason)) skipped: settings/keyWindow still key")
                return
            }
        }

        // 如果全盘搜索可见：严禁因 windowResigned 或 appDeactivated 关闭全盘搜索，仅在应用明确切换或外部点击时遵循收拢
        if searchPanelCreated && searchPanel.isVisible {
            if reason == .windowResigned || reason == .appDeactivated {
                runtimeLog("[Panel] autoDismiss(\(reason)) skipped: search panel preserves state for auxiliary floating tools.")
                return
            }
            hideSearchPanel(restoreFocus: false)
        }

        // 如果应用抽屉可见：固定在桌面时受绝对保护，绝不响应失焦退出；未固定时遵循自动收起策略
        if shelfPanelCreated && shelfPanel.isVisible {
            if isShelfPinned {
                runtimeLog("[Panel] autoDismiss(\(reason)) skipped: shelf is pinned to desktop")
                return
            }
            let decision = PanelDismissPolicy.shouldDismiss(
                activePanel: .shelf,
                isShelfPinned: isShelfPinned,
                autoCloseOnDeactivate: ConfigManager.shared.config.autoCloseOnDeactivate,
                isDraggingActive: isDraggingActive,
                hasModalWindow: NSApp.modalWindow != nil,
                isSettingsWindowKey: SettingsWindowController.isSettingsWindowKey,
                isRightClickMenuOpen: isRightClickMenuOpen
            )
            runtimeLog("[Panel] autoDismiss reason=\(reason) panel=shelf decision=\(decision)")
            if decision {
                hideShelfPanel(restoreFocus: false)
            }
        }
    }

    /// 初始化时把面板固定按钮状态同步到当前配置值。
    public func refreshShelfPinState() {
        guard shelfPanelCreated else { return }
        shelfPanel.shelfViewController.updatePinButtonState(isPinned: ConfigManager.shared.config.isShelfPinned)
    }

    public func showShelfPanel() {
        guard ConfigManager.shared.config.enableShelfPanel else { return }
        panelPresentationGeneration &+= 1
        recordPreviousFrontmostAppIfNeeded()

        shelfPanel.prepareForDisplay()
        positionPanelFollowMouse(shelfPanel)
        animatePanelEntrance(shelfPanel)
        NSApp.activate(ignoringOtherApps: true)
        shelfPanel.makeKeyAndOrderFront(nil)
        shelfPanel.orderFrontRegardless()
        shelfPanel.makeKey()

        activePanel = .shelf
        installGlobalOutsideClickMonitor()
    }

    public func hideShelfPanel(restoreFocus: Bool = true, animated: Bool = true, forceHidePinned: Bool = false) {
        guard shelfPanelCreated && shelfPanel.isVisible else { return }
        if isShelfPinned && !forceHidePinned {
            runtimeLog("[Panel] hideShelfPanel ignored: shelf is pinned to desktop")
            return
        }
        panelPresentationGeneration &+= 1
        let generation = panelPresentationGeneration
        runtimeLog("[Panel] hideShelfPanel gen=\(generation) restoreFocus=\(restoreFocus) forceHidePinned=\(forceHidePinned)")

        if activePanel == .shelf {
            activePanel = (searchPanelCreated && searchPanel.isVisible) ? .search : nil
        }

        if animated {
            animatePanelDismissal(shelfPanel, generation: generation)
        } else {
            shelfPanel.orderOut(nil)
            resetPanelEntrance(shelfPanel)
        }

        if activePanel == nil {
            stopGlobalOutsideClickMonitor()
            restoreFocusIfNeeded(restoreFocus: restoreFocus)
            MemoryGuardian.shared.onPanelsDidHide()
        }
    }

    public func showSearchPanel() {
        guard ConfigManager.shared.config.enableSearchPanel else { return }
        panelPresentationGeneration &+= 1
        recordPreviousFrontmostAppIfNeeded()

        // 仅在抽屉未固定时收起抽屉；若抽屉已固定在桌面（isShelfPinned），绝不收起抽屉，两者在屏幕上优雅并存！
        if !isShelfPinned && shelfPanelCreated && shelfPanel.isVisible {
            hideShelfPanel(restoreFocus: false, animated: false)
        }

        // 检查并消费外部剪贴板最近 3 秒内的复制内容
        let prefilled = PasteboardRecencyTracker.shared.checkAndConsumePasteContent()

        AppHotspotIndex.shared.refreshIfStale()
        searchPanel.prepareForDisplay(prefilledText: prefilled)
        searchPanel.markSummonPasteboardState()
        positionPanelToScreenCenter(searchPanel)
        animatePanelEntrance(searchPanel)
        NSRunningApplication.current.activate(options: .activateIgnoringOtherApps)
        NSApp.activate(ignoringOtherApps: true)
        searchPanel.makeKeyAndOrderFront(nil)
        searchPanel.orderFrontRegardless()
        searchPanel.makeKey()
        searchPanel.makeMain()

        activePanel = .search
        installGlobalOutsideClickMonitor()
    }

    public func hideSearchPanel(restoreFocus: Bool = true, animated: Bool = true) {
        guard searchPanelCreated && searchPanel.isVisible else { return }
        panelPresentationGeneration &+= 1
        let generation = panelPresentationGeneration
        runtimeLog("[Panel] hideSearchPanel gen=\(generation) restoreFocus=\(restoreFocus)")

        if activePanel == .search {
            activePanel = (shelfPanelCreated && shelfPanel.isVisible) ? .shelf : nil
        }

        if animated {
            animatePanelDismissal(searchPanel, generation: generation)
        } else {
            searchPanel.orderOut(nil)
            resetPanelEntrance(searchPanel)
        }

        if activePanel == nil {
            stopGlobalOutsideClickMonitor()
            restoreFocusIfNeeded(restoreFocus: restoreFocus)
            MemoryGuardian.shared.onPanelsDidHide()
        } else if activePanel == .shelf {
            if isShelfPinned {
                restoreFocusIfNeeded(restoreFocus: restoreFocus)
            }
        }
    }

    public func togglePanel(_ kind: PanelKind, animated: Bool = true) {
        switch kind {
        case .shelf:
            guard ConfigManager.shared.config.enableShelfPanel else { return }
            let isVisible = shelfPanelCreated && shelfPanel.isVisible
            runtimeLog("[Panel] toggle shelf: isVisible=\(isVisible)")
            if isVisible {
                hideShelfPanel(animated: animated, forceHidePinned: true)
            } else {
                showShelfPanel()
            }
        case .search:
            guard ConfigManager.shared.config.enableSearchPanel else { return }
            let isVisible = searchPanelCreated && searchPanel.isVisible
            runtimeLog("[Panel] toggle search: isVisible=\(isVisible)")
            if isVisible {
                hideSearchPanel(animated: animated)
            } else {
                showSearchPanel()
            }
        }
    }

    public func switchToPanel(_ target: PanelKind) {
        runtimeLog("[Panel] switchToPanel(\(target))")
        switch target {
        case .shelf: showShelfPanel()
        case .search: showSearchPanel()
        }
    }

    public func hideAllPanels(restoreFocus: Bool = true, animated: Bool = true, forceHidePinnedShelf: Bool = false) {
        panelPresentationGeneration &+= 1
        let generation = panelPresentationGeneration
        let wasShowingPanel = (shelfPanelCreated && shelfPanel.isVisible) || (searchPanelCreated && searchPanel.isVisible)
        runtimeLog("[Panel] hideAllPanels wasShowing=\(wasShowingPanel) gen=\(generation) restoreFocus=\(restoreFocus) forceHidePinned=\(forceHidePinnedShelf)")
        isDraggingActive = false

        var panelsToHide: [NSPanel] = []
        if searchPanelCreated && searchPanel.isVisible {
            panelsToHide.append(searchPanel)
        }
        if shelfPanelCreated && shelfPanel.isVisible {
            if !isShelfPinned || forceHidePinnedShelf {
                panelsToHide.append(shelfPanel)
            }
        }

        if panelsToHide.contains(where: { $0 === shelfPanel }) {
            activePanel = nil
        } else if shelfPanelCreated && shelfPanel.isVisible {
            activePanel = .shelf
        } else {
            activePanel = nil
        }

        if activePanel == nil {
            stopGlobalOutsideClickMonitor()
        }

        for panel in panelsToHide {
            if animated {
                animatePanelDismissal(panel, generation: generation)
            } else {
                panel.orderOut(nil)
                resetPanelEntrance(panel)
            }
        }

        restoreFocusIfNeeded(restoreFocus: restoreFocus)
        if activePanel == nil {
            MemoryGuardian.shared.onPanelsDidHide()
        }
    }

    private func animatePanelEntrance(_ panel: NSPanel) {
        let duration: TimeInterval = 0.16
        let timing = CAMediaTimingFunction(controlPoints: 0.2, 0.0, 0.0, 1.0)

        panel.alphaValue = 0.0

        if let contentView = panel.contentView {
            contentView.wantsLayer = true
            guard let layer = contentView.layer else { return }

            let bounds = contentView.bounds
            let transform = CATransform3DIdentity
            let scaleFactor: CGFloat = 0.96
            let scaled = CATransform3DScale(transform, scaleFactor, scaleFactor, 1.0)
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
                guard let self = self, let panel = panel else { return }
                guard self.panelPresentationGeneration == generation else {
                    runtimeLog("[Panel] dismiss completion SKIPPED (gen changed \(generation)→\(self.panelPresentationGeneration)) panel=\(panel) visible=\(panel.isVisible)")
                    return
                }
                panel.orderOut(nil)
                self.resetPanelEntrance(panel)
                runtimeLog("[Panel] orderOut done panel=\(panel) visibleAfter=\(panel.isVisible) alpha=\(panel.alphaValue)")
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
        guard (shelfPanelCreated && shelfPanel.isVisible) || (searchPanelCreated && searchPanel.isVisible) else { return }
        if isDraggingActive || NSApp.modalWindow != nil { return }
        if isRightClickMenuOpen { return }

        let clickLoc = NSEvent.mouseLocation
        if let settingsFrame = SettingsWindowController.visibleWindowFrame, NSPointInRect(clickLoc, settingsFrame) {
            return
        }

        // 若全盘搜索处于打开状态，点击搜索区域外部时仅收回搜索
        if searchPanelCreated && searchPanel.isVisible {
            let visibleFrame = (searchPanel as PanelVisibleFrameProviding).visiblePanelFrame
            if !NSPointInRect(clickLoc, visibleFrame) {
                // 关键保护：若点击发生在辅助浮层工具（如剪贴板管理器 AuraSnap、Maccy 等窗口）上，绝不收回搜索面板，等待用户选取条目
                if Self.isClickOnAuxiliaryToolWindow(at: clickLoc) {
                    runtimeLog("[Panel] handleOutsideInteraction: click is on auxiliary/clipboard tool window, preserving search panel.")
                    return
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if self.isDraggingActive || NSApp.modalWindow != nil || self.isRightClickMenuOpen { return }
                    // 再次检查此时是否发生了剪贴板协同变动
                    let initialCount = self.searchPanel.summonPasteboardChangeCount
                    if NSPasteboard.general.changeCount > initialCount {
                        runtimeLog("[Panel] handleOutsideInteraction: pasteboard updated, preserving search panel.")
                        return
                    }
                    self.hideSearchPanel(restoreFocus: true)
                }
            }
            return
        }

        // 仅应用抽屉可见时，若已固定在桌面，点击外部绝不收起；未固定时按外部点击收起
        if shelfPanelCreated && shelfPanel.isVisible {
            if isShelfPinned { return }
            let visibleFrame = shelfPanel.frame
            if !NSPointInRect(clickLoc, visibleFrame) {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    if self.isDraggingActive || NSApp.modalWindow != nil || self.isRightClickMenuOpen { return }
                    if self.isShelfPinned { return }
                    self.hideShelfPanel(restoreFocus: true)
                }
            }
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

    private static let knownAuxiliaryToolIdentifiers: Set<String> = [
        "com.dochi.AuraSnap",
        "org.p0deje.Maccy",
        "com.pasteapp.Paste",
        "com.apptorium.Pastebot",
        "com.clipy-app.Clipy",
        "com.mzperx.CleanClip",
        "com.knollsoft.AltTab"
    ]

    /// 检查点击的屏幕坐标是否落在辅助浮层工具（如 AuraSnap、Maccy、Paste、CleanClip 等无 Dock 图标的工具面板）的窗口范围内
    internal static func isClickOnAuxiliaryToolWindow(at screenPoint: NSPoint) -> Bool {
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? 900
        let quartzY = mainScreenHeight - screenPoint.y

        // Tier 1: 优先尝试通过系统 Accessibility API (AXUIElement) 获取点击点所在的进程 PID
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.05) // 50ms 严格超时保护，绝不拖卡主线程
        var element: AXUIElement?
        let axErr = AXUIElementCopyElementAtPosition(systemWide, Float(screenPoint.x), Float(quartzY), &element)
        if axErr == .success, let elem = element {
            var pid: pid_t = 0
            if AXUIElementGetPid(elem, &pid) == .success && pid > 0 {
                if pid == ProcessInfo.processInfo.processIdentifier {
                    return true // 自身窗口
                }
                if let app = NSRunningApplication(processIdentifier: pid) {
                    let bundleID = app.bundleIdentifier ?? ""
                    if bundleID == "com.apple.dock" || bundleID == "com.apple.controlcenter" || bundleID == "com.apple.systemuiserver" {
                        return false
                    }
                    if app.activationPolicy == .accessory || app.activationPolicy == .prohibited {
                        return true
                    }
                    if knownAuxiliaryToolIdentifiers.contains(bundleID) {
                        return true
                    }
                }
            }
        }

        // Tier 2: 若 AX 降级或未命中，检查系统当前运行中是否处于活跃状态的已知辅助/剪贴板工具
        for runningApp in NSWorkspace.shared.runningApplications {
            if runningApp.activationPolicy == .accessory,
               let bid = runningApp.bundleIdentifier,
               knownAuxiliaryToolIdentifiers.contains(bid) {
                return true
            }
        }

        return false
    }
}
