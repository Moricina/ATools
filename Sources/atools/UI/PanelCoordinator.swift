import Foundation
import AppKit

public enum PanelKind {
    case shelf   // 面板 A: Maye Nano 风格分类抽屉
    case search  // 面板 B: Spotlight 风格全盘搜索
}

public final class PanelCoordinator {
    public static let shared = PanelCoordinator()

    private var shelfPanelCreated = false

    public private(set) lazy var shelfPanel: ShelfPanel = {
        shelfPanelCreated = true
        return ShelfPanel()
    }()

    public private(set) lazy var searchPanel: SearchPanel = SearchPanel()

    private var activePanel: PanelKind?
    private var globalClickMonitor: Any?

    /// 标记当前是否正处于向外部 App 拖拽文件的会话中，拖拽期间屏蔽一切外部失焦销毁
    public var isDraggingActive: Bool = false

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

    private init() {}

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
        if target == .shelf && !ConfigManager.shared.config.enableShelfPanel { return }
        if target == .search && !ConfigManager.shared.config.enableSearchPanel { return }

        // 1. Atomically order out any previously active panel (no overlap)
        if let current = activePanel, current != target {
            let panelToHide = (current == .shelf) ? shelfPanel : searchPanel
            panelToHide.orderOut(nil)
            activePanel = nil
        }
        switch target {
        case .shelf:
            // 鼠标跟随定位 + 多屏可见区域 Clamping
            positionPanelFollowMouse(shelfPanel)
            NSApp.activate(ignoringOtherApps: true)
            shelfPanel.makeKeyAndOrderFront(nil)
            shelfPanel.orderFrontRegardless()
            shelfPanel.prepareForDisplay()
        case .search:
            // Prepare for display (resets to 72pt height) before calculating screen anchor
            searchPanel.prepareForDisplay()
            positionPanelToScreenCenter(searchPanel)
            NSApp.activate(ignoringOtherApps: true)
            searchPanel.makeKeyAndOrderFront(nil)
        }

        activePanel = target
        installGlobalOutsideClickMonitor()
    }

    public func hideAllPanels() {
        isDraggingActive = false
        stopGlobalOutsideClickMonitor()

        shelfPanel.orderOut(nil)
        searchPanel.orderOut(nil)
        activePanel = nil

        MemoryGuardian.shared.onPanelsDidHide()
    }

    private func installGlobalOutsideClickMonitor() {
        stopGlobalOutsideClickMonitor()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseDown]) { [weak self] _ in
            guard let self = self, let active = self.activePanel else { return }
            if self.isDraggingActive { return }
            // Do not dismiss panel if a modal alert/window is currently presented or Settings window is clicked
            if NSApp.modalWindow != nil { return }
            let clickLoc = NSEvent.mouseLocation
            if let settingsWin = SettingsWindowController.shared.window, settingsWin.isVisible && NSPointInRect(clickLoc, settingsWin.frame) {
                return
            }

            // 核心隔离：工作台处于 Pinned 状态或未开启失焦关闭时，外部点击不关闭
            if active == .shelf && (self.isShelfPinned || !ConfigManager.shared.config.autoCloseOnDeactivate) {
                return
            }

            let currentPanel = (active == .shelf) ? self.shelfPanel : self.searchPanel

            if !NSPointInRect(clickLoc, currentPanel.frame) {
                self.hideAllPanels()
            }
        }
    }

    private func stopGlobalOutsideClickMonitor() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
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
            // Anchor search bar top to natural eye level (66% from bottom of visible frame)
            let y = visible.origin.y + (visible.height * 0.66) - panel.frame.height
            panel.setFrameOrigin(NSPoint(x: x, y: y))
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
