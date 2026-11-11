import Foundation
import AppKit

/// 边缘感应协调器：管理屏幕边缘触碰侦测、多边缘自适应与防抖唤出
public final class EdgeDockSensorCoordinator {
    public static let shared = EdgeDockSensorCoordinator()

    /// 边缘唤出回调，返回具体的触碰边缘（.left / .right / .top）
    public var onEdgeTriggered: ((ShelfDockEdge) -> Void)?

    private var globalMouseMoveMonitor: Any?
    private var localMouseMoveMonitor: Any?
    private var hoverWorkItem: DispatchWorkItem?
    private var pendingEdge: ShelfDockEdge?
    private var isMonitoring: Bool = false

    // 微型边缘锚定窗口（辅助保持 WindowServer 响应链激活）
    private var anchorWindows: [ShelfDockEdge: NSPanel] = [:]

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateAnchorWindows()
        }
    }

    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        cancelPendingTrigger()
        installMouseMonitors()
        updateAnchorWindows()
    }

    public func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        cancelPendingTrigger()
        removeMouseMonitors()
        hideAnchorWindows()
    }

    public func cancelPendingTrigger() {
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
        pendingEdge = nil
    }

    private func installMouseMonitors() {
        removeMouseMonitors()

        globalMouseMoveMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] event in
            self?.handleMouseMoved(NSEvent.mouseLocation)
        }

        localMouseMoveMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        ) { [weak self] event in
            self?.handleMouseMoved(NSEvent.mouseLocation)
            return event
        }
    }

    private func removeMouseMonitors() {
        if let g = globalMouseMoveMonitor {
            NSEvent.removeMonitor(g)
            globalMouseMoveMonitor = nil
        }
        if let l = localMouseMoveMonitor {
            NSEvent.removeMonitor(l)
            localMouseMoveMonitor = nil
        }
    }

    /// 核心边缘判定与防抖状态机
    private func handleMouseMoved(_ mouseLoc: NSPoint) {
        guard isMonitoring else { return }

        // 获取当前光标所在的屏幕
        let targetScreen = NSScreen.screens.first { NSPointInRect(mouseLoc, $0.frame) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen = targetScreen else { return }

        let visible = screen.visibleFrame
        let cornerMargin: CGFloat = 32.0 // 避开屏幕四角系统触发角 (Hot Corners)

        let configEdge = ConfigManager.shared.config.shelfDockEdge
        let detectedEdge: ShelfDockEdge?

        // 1. 检测左边缘
        let inLeftZone = (mouseLoc.x <= visible.minX + 3.0) &&
                         (mouseLoc.y >= visible.minY + cornerMargin) &&
                         (mouseLoc.y <= visible.maxY - cornerMargin)

        // 2. 检测右边缘
        let inRightZone = (mouseLoc.x >= visible.maxX - 3.0) &&
                          (mouseLoc.y >= visible.minY + cornerMargin) &&
                          (mouseLoc.y <= visible.maxY - cornerMargin)

        switch configEdge {
        case .left:
            detectedEdge = inLeftZone ? .left : nil
        case .right:
            detectedEdge = inRightZone ? .right : nil
        case .autoNearest:
            // 自适应两侧：靠近哪边就从哪边唤出，避开系统顶栏冲突
            if inLeftZone {
                detectedEdge = .left
            } else if inRightZone {
                detectedEdge = .right
            } else {
                detectedEdge = nil
            }
        }

        if let edge = detectedEdge {
            if pendingEdge == edge && hoverWorkItem != nil {
                // 已经在等待触发当前边缘，保持计时
                return
            }
            // 开启新边缘悬停防抖
            cancelPendingTrigger()
            pendingEdge = edge

            let delayMs = ConfigManager.shared.config.shelfDockDelayMs
            let delaySec = Double(delayMs) / 1000.0

            let work = DispatchWorkItem { [weak self] in
                guard let self = self, self.isMonitoring else { return }
                guard self.pendingEdge == edge else { return }
                self.cancelPendingTrigger()
                self.onEdgeTriggered?(edge)
            }
            hoverWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delaySec, execute: work)
        } else {
            // 光标离开边缘区域：如果已离开一定距离（> 16pt），立即取消等待
            let isNearAnyEdge = (mouseLoc.x <= visible.minX + 16.0) ||
                                (mouseLoc.x >= visible.maxX - 16.0)
            if !isNearAnyEdge {
                cancelPendingTrigger()
            }
        }
    }

    private func updateAnchorWindows() {
        guard isMonitoring else {
            hideAnchorWindows()
            return
        }
        let mouseLoc = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { NSPointInRect(mouseLoc, $0.frame) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen = activeScreen else { return }
        let visible = screen.visibleFrame
        let thickness: CGFloat = 2.0
        let cornerMargin: CGFloat = 32.0

        let edgesToDeploy: [ShelfDockEdge]
        switch ConfigManager.shared.config.shelfDockEdge {
        case .left: edgesToDeploy = [.left]
        case .right: edgesToDeploy = [.right]
        case .autoNearest: edgesToDeploy = [.left, .right]
        }

        for edge in edgesToDeploy {
            let panel = anchorWindows[edge] ?? makeAnchorWindow()
            anchorWindows[edge] = panel

            var rect: NSRect = .zero
            switch edge {
            case .left:
                let h = max(100, visible.height - cornerMargin * 2)
                rect = NSRect(x: visible.minX, y: visible.minY + cornerMargin, width: thickness, height: h)
            case .right:
                let h = max(100, visible.height - cornerMargin * 2)
                rect = NSRect(x: visible.maxX - thickness, y: visible.minY + cornerMargin, width: thickness, height: h)
            case .autoNearest:
                break
            }

            if rect != .zero {
                panel.setFrame(rect, display: true)
                panel.orderFrontRegardless()
            }
        }

        // 隐藏未部署的边缘窗口
        for (edge, panel) in anchorWindows where !edgesToDeploy.contains(edge) {
            panel.orderOut(nil)
        }
    }

    private func hideAnchorWindows() {
        for (_, panel) in anchorWindows {
            panel.orderOut(nil)
        }
    }

    private func makeAnchorWindow() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true // 点击直接穿透，由全局监视器精准负责唤出
        return panel
    }
}
