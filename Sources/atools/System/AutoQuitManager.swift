import Foundation
import AppKit
import ApplicationServices

/// macOS 辅助功能私有/标准常量补全
private let kAXWindowClosedNotification = "AXWindowClosed" as CFString

/// AXObserver 的 C 回调跳板：C 函数指针无法捕获上下文，单例又永不释放，因此直接转发
/// 给 shared；归属进程用 AXUIElementGetPid 从被观察元素反查，不依赖 refcon。
private let autoQuitObserverCallback: AXObserverCallback = { _, element, notification, _ in
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success, pid != 0 else { return }
    AutoQuitManager.shared.handleAXNotification(
        pid: pid,
        element: element,
        notificationName: (notification as String?) ?? ""
    )
}

/// AutoQuit：应用最后一个窗口关闭后，延迟自动退出该应用（对标 SwiftQuit）。
///
/// 权限：依赖「辅助功能」(AX API) 监听其他应用的窗口事件。总开关默认关闭；
/// 未授权时 startIfEnabled() 静默保持空闲，绝不主动弹 TCC prompt——授权引导只在
/// 设置页用户显式点击开关或授权按钮时出现（见 GeneralTabView）。
///
/// 线程模型：AXObserver 挂在主 RunLoop 的 commonModes，兜底 Timer 也在主线程，
/// 因此全部状态只在主线程读写（与无锁、仅主线程读写的 ConfigManager 匹配）；
/// os_unfair_lock 仅用于 start/stop 防重入，与 TrackpadGestureManager 同一模式。
public final class AutoQuitManager {
    public static let shared = AutoQuitManager()

    /// 硬排除的系统应用：退出 Finder 会被 launchd 立即拉起，其余为常驻系统服务。
    public static let systemExcludedBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.Spotlight",
        "com.apple.notificationcenterui",
        "com.apple.dock"
    ]

    private struct WatchedApp {
        let app: NSRunningApplication
        let axApp: AXUIElement
        let observer: AXObserver
        /// 已注册销毁通知的窗口元素，用于窗口新建时去重注册。
        var registeredWindowRefs: [AXUIElement]
        /// 最近一次确认时是否拥有窗口。零窗口应用（登录项、后台 utility）绝不直接
        /// 退出，只有从「有窗」跌落到「确认零窗」才调度退出。
        var hadWindows: Bool
    }

    private var watched: [pid_t: WatchedApp] = [:]
    private var pendingQuits: [pid_t: DispatchWorkItem] = [:]
    private var terminatingPids: Set<pid_t> = []
    private var recheckCounts: [pid_t: Int] = [:]
    private var fallbackTimer: Timer?
    private var isRunning = false
    private var lock = os_unfair_lock()
    private var lastSpaceChangeDate: Date = .distantPast

    private var defaultCenterObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    private init() {
        // 配置变更（设置页 / 状态栏菜单）驱动监视集合全量重建
        defaultCenterObservers.append(NotificationCenter.default.addObserver(
            forName: .atoolsAutoQuitDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateConfiguration()
        })

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self, self.isRunning,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.attachIfEligible(app)
        })
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.detach(pid: app.processIdentifier)
        })
        // 监听虚拟桌面 (Spaces) 切换：Space 切换时 WindowServer 与 AX 处于过渡态，设立保护宽限期防止误杀
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.lastSpaceChangeDate = Date()
        })
        // 睡眠唤醒后其他应用的 AX 树可能整体失效，与 TrackpadGestureManager 一致地重建
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            self.rebuild()
        })
    }

    deinit {
        for token in defaultCenterObservers {
            NotificationCenter.default.removeObserver(token)
        }
        for token in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }

    // MARK: - 生命周期入口

    /// 应用启动时调用。开关未开或未授权时保持空闲且静默（不弹任何系统弹窗）。
    public func startIfEnabled() {
        assert(Thread.isMainThread)
        let cfg = ConfigManager.shared.config
        guard cfg.enableAutoQuit else {
            stop()
            return
        }
        guard HotkeyManager.isAccessibilityTrusted() else {
            runtimeLog("[AutoQuit] Enabled but Accessibility not granted yet; staying idle.")
            stop()
            return
        }
        start()
    }

    /// didBecomeActive 钩子：用户可能刚在系统设置里完成授权，切回后热启动。
    /// 状态发生翻转时广播通知，让设置页的授权状态行与状态栏菜单同步。
    public func reloadIfTrusted() {
        assert(Thread.isMainThread)
        let wasRunning = isRunning
        startIfEnabled()
        if isRunning != wasRunning {
            NotificationCenter.default.post(name: .atoolsAutoQuitDidChange, object: nil)
        }
    }

    /// 配置（开关/模式/名单/延迟）变化后的全量重建。
    public func updateConfiguration() {
        assert(Thread.isMainThread)
        rebuild()
    }

    private func rebuild() {
        stop()
        startIfEnabled()
    }

    // MARK: - 监视资格（纯函数，供 --test 直接断言，不触碰单例状态）

    /// 监视资格判定。nil bundleID 的进程（裸二进制）保守跳过；onlyListed 模式下
    /// nil 永不匹配；allApps 模式下名单是排除项，onlyListed 模式下名单是包含项。
    public static func shouldWatch(
        bundleID: String?,
        activationPolicy: NSApplication.ActivationPolicy,
        isFinishedLaunching: Bool,
        isSelf: Bool,
        mode: AutoQuitMode,
        rules: [String]
    ) -> Bool {
        guard !isSelf else { return false }
        guard activationPolicy == .regular else { return false }
        guard isFinishedLaunching else { return false }
        guard let bid = bundleID, !bid.isEmpty else { return false }
        guard !systemExcludedBundleIDs.contains(bid) else { return false }
        switch mode {
        case .allApps: return !rules.contains(where: { $0.caseInsensitiveCompare(bid) == .orderedSame })
        case .onlyListed: return rules.contains(where: { $0.caseInsensitiveCompare(bid) == .orderedSame })
        }
    }

    /// 零窗判定（纯函数）：AX 查询失败（nil）绝不能视为零窗，否则 AX 树失效的
    /// 应用会在「最后一个窗口关闭」前就被误杀。
    public static func isConfirmedZeroWindowCount(_ count: Int?) -> Bool {
        return count == 0
    }

    /// 双重权威校验纯函数：结合 AX 窗口计数与 WindowServer 真实窗口层。
    /// 当 WindowServer 显示仍有标准业务窗口时（如应用失焦、多虚拟桌面切换、第三方应用 AX 延迟响应），
    /// 无论 AX 返回何值，均绝对不能视为零窗；只有双方均确认为零（或 WindowServer 确认无窗）才确诊。
    public static func isConfirmedZeroWindowCount(axCount: Int?, windowServerCount: Int?) -> Bool {
        // 1. 若 WindowServer 确认仍存在 >= 1 个标准窗口，绝不能判定为零窗！
        // 这一步彻底防止了「用户未点最小化、仅切换应用/点击其他应用」导致的意外退出。
        if let ws = windowServerCount, ws > 0 {
            return false
        }
        // 2. 若 AX 查询失败（nil），状态未知，保守放行，决不误杀
        guard let ax = axCount else {
            return false
        }
        // 3. 只有两者均确认无标准窗口（AX 为 0 且 WindowServer 也为 0 或不可用但 AX 确证 0）才确诊
        if ax == 0 {
            if let ws = windowServerCount {
                return ws == 0
            }
            return true
        }
        return false
    }

    /// WindowServer 层面标准应用窗口计数（Layer 0...150，有效尺寸，排除离屏缓存与极小隐形辅助窗口）
    public static func windowServerStandardWindowCount(for pid: pid_t) -> Int? {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let systemProxies: Set<String> = [
            "Touch Bar", "Focus Proxy", "Item Status", "Emoji & Symbols", "FocusProxy"
        ]
        let internalCefViews: Set<String> = [
            "ConvTabListView", "ConvTabTopBar", "MainMenuPanelView", "Form"
        ]

        var count = 0
        for w in list {
            guard let ownerPID = w[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else { continue }
            guard let layer = w[kCGWindowLayer as String] as? Int, (0...150).contains(layer) else { continue }
            guard let alpha = w[kCGWindowAlpha as String] as? Double, alpha > 0.01 else { continue }
            guard let bounds = w[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double,
                  width > 40, height > 40 else { continue }

            // 关键：必须是在屏（On-Screen）有效窗口！已关闭/orderedOut 隐藏的窗口 isOnScreen 为 false
            guard let isOnScreen = w[kCGWindowIsOnscreen as String] as? Bool, isOnScreen else { continue }

            let rawName = (w[kCGWindowName as String] as? String) ?? ""
            let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)

            if systemProxies.contains(trimmedName) { continue }
            if internalCefViews.contains(trimmedName) { continue }

            // 钉钉特定的常驻后台/隐形登录弹窗 (500x372)
            if abs(width - 500) < 15 && abs(height - 372) < 15 { continue }

            if !trimmedName.isEmpty {
                // 有标题的标准窗口（Safari 页面、Chrome 标签页、终端窗口、钉钉主窗口等）：
                // 无论是否失焦、是否在其他 Space、是否被遮挡，一律确认为有效窗口！
                count += 1
                continue
            }

            // 无标题窗口过滤（系统常驻残影、离屏缓冲、AppKit 占位层）
            // 1. AppKit 500x500 占位层
            if abs(width - 500) < 25 && abs(height - 500) < 25 { continue }
            // 2. 菜单栏/工具栏横条 (height <= 48)
            if height <= 48 { continue }
            // 3. 小型代理/光标/状态图标
            if width <= 80 && height <= 60 { continue }
            // 4. CEF 离屏缓冲画布 (640x508, 600x600)
            if abs(width - 640) < 20 && abs(height - 508) < 20 { continue }
            if abs(width - 600) < 20 && abs(height - 600) < 20 { continue }

            // 具有合理尺寸的无标题真实窗口（如部分 Electron/Flutter/Java 无标题主窗体）
            if width > 120 && height > 90 {
                count += 1
            }
        }
        return count
    }

    /// 实例级别零窗确认：结合当前进程的 AX 查询与 WindowServer 计数
    public static func isConfirmedZeroWindows(pid: pid_t, axCount: Int?) -> Bool {
        let wsCount = windowServerStandardWindowCount(for: pid)
        return isConfirmedZeroWindowCount(axCount: axCount, windowServerCount: wsCount)
    }

    private func shouldAttach(_ app: NSRunningApplication) -> Bool {
        let cfg = ConfigManager.shared.config
        return AutoQuitManager.shouldWatch(
            bundleID: app.bundleIdentifier,
            activationPolicy: app.activationPolicy,
            isFinishedLaunching: app.isFinishedLaunching,
            isSelf: app.processIdentifier == ProcessInfo.processInfo.processIdentifier,
            mode: cfg.autoQuitMode,
            rules: cfg.autoQuitAppRules
        )
    }

    // MARK: - 内部状态机（所有 *_locked 变体假定已持锁且在主线程）

    private func start() {
        assert(Thread.isMainThread)
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        guard !isRunning else { return }
        isRunning = true

        for app in NSWorkspace.shared.runningApplications {
            attachLocked(app)
        }

        // 兜底轮询：捕获不吐 AX 销毁事件的应用（部分 Electron/Java/CEF）。
        // 仅扫 hadWindows 的应用，每 2.0s 一次轻量查询，代价可忽略。
        let timer = Timer(timeInterval: 2.0, target: self, selector: #selector(fallbackPoll), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        fallbackTimer = timer
        runtimeLog("[AutoQuit] Started; watching \(watched.count) regular app(s).")
    }

    public func stop() {
        assert(Thread.isMainThread)
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        guard isRunning || !watched.isEmpty else { return }
        for work in pendingQuits.values {
            work.cancel()
        }
        pendingQuits.removeAll()
        terminatingPids.removeAll()
        recheckCounts.removeAll()
        for entry in watched.values {
            teardownObserver(entry.observer)
        }
        watched.removeAll()
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        isRunning = false
        runtimeLog("[AutoQuit] Stopped; all AX observers released.")
    }

    private func attachIfEligible(_ app: NSRunningApplication) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        attachLocked(app)
    }

    private func detach(pid: pid_t) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        cancelPendingQuitLocked(pid)
        terminatingPids.remove(pid)
        recheckCounts.removeValue(forKey: pid)
        if let entry = watched.removeValue(forKey: pid) {
            teardownObserver(entry.observer)
        }
    }

    private func attachLocked(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard watched[pid] == nil else { return }
        guard shouldAttach(app) else { return }

        var observer: AXObserver?
        let createErr = AXObserverCreate(pid, autoQuitObserverCallback, &observer)
        guard createErr == .success, let obs = observer else {
            runtimeLog("[AutoQuit] AXObserverCreate failed for pid \(pid): error \(createErr.rawValue)")
            return
        }
        // commonModes 保证菜单追踪、模态会话期间 AX 事件不被暂停
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)

        let axApp = AXUIElementCreateApplication(pid)
        // 关键防卡死：设置 150ms 消息超时，防止被监视应用卡死/无响应时拖死 ATools 主线程
        AXUIElementSetMessagingTimeout(axApp, 0.15)
        let addErr = AXObserverAddNotification(obs, axApp, kAXWindowCreatedNotification as CFString, nil)
        if addErr != .success {
            runtimeLog("[AutoQuit] AddNotification(WindowCreated) failed for pid \(pid): error \(addErr.rawValue)")
        }
        _ = AXObserverAddNotification(obs, axApp, kAXWindowClosedNotification, nil)
        _ = AXObserverAddNotification(obs, axApp, kAXUIElementDestroyedNotification as CFString, nil)

        var entry = WatchedApp(
            app: app,
            axApp: axApp,
            observer: obs,
            registeredWindowRefs: [],
            hadWindows: false
        )
        // 为现有窗口注册销毁通知；初始窗口数决定 hadWindows（零窗口应用绝不直接退出）
        let existing = axWindows(of: axApp)
        let wsCount = AutoQuitManager.windowServerStandardWindowCount(for: pid)
        if let list = existing, !list.isEmpty {
            entry.hadWindows = true
            for window in list {
                if AXObserverAddNotification(obs, window, kAXUIElementDestroyedNotification as CFString, nil) == .success {
                    entry.registeredWindowRefs.append(window)
                }
            }
        } else if let ws = wsCount, ws > 0 {
            entry.hadWindows = true
        }
        watched[pid] = entry
        let knownCount = existing.map { String($0.count) } ?? (wsCount.map { "ws:\($0)" } ?? "unknown")
        runtimeLog("[AutoQuit] Watching \(app.localizedName ?? "pid \(pid)") (windows: \(knownCount))")
    }

    func handleAXNotification(pid: pid_t, element: AXUIElement, notificationName: String) {
        assert(Thread.isMainThread)
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        guard isRunning, var entry = watched[pid] else { return }

        if notificationName == kAXWindowCreatedNotification as String {
            terminatingPids.remove(pid)
            recheckCounts.removeValue(forKey: pid)
            // 新窗口：注册其销毁通知；若窗口重新出现，取消挂起的退出
            if !entry.registeredWindowRefs.contains(where: { CFEqual($0, element) }) {
                if AXObserverAddNotification(entry.observer, element, kAXUIElementDestroyedNotification as CFString, nil) == .success {
                    entry.registeredWindowRefs.append(element)
                }
            }
            let axCount = axWindows(of: entry.axApp)?.count
            if (axCount ?? 0) > 0 {
                entry.hadWindows = true
                watched[pid] = entry
                cancelPendingQuitLocked(pid)
            } else {
                let wsCount = AutoQuitManager.windowServerStandardWindowCount(for: pid)
                if (wsCount ?? 0) > 0 {
                    entry.hadWindows = true
                    watched[pid] = entry
                    cancelPendingQuitLocked(pid)
                }
            }
        } else if notificationName == (kAXWindowClosedNotification as String)
                    || notificationName == (kAXUIElementDestroyedNotification as String) {
            guard entry.hadWindows else { return }
            evaluateAppWindowsLocked(pid: pid)
        }
    }

    private func evaluateAppWindows(pid: pid_t) {
        assert(Thread.isMainThread)
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        evaluateAppWindowsLocked(pid: pid)
    }

    private func evaluateAppWindowsLocked(pid: pid_t) {
        guard isRunning, var entry = watched[pid] else { return }
        let app = entry.app
        guard !app.isTerminated else { return }

        // 安全防护 1：用户使用 Cmd+H 隐藏的应用绝不能自动退出
        guard !app.isHidden else { return }

        // 安全防护 2：Space 虚拟桌面切换过渡期内（2秒内）冻结零窗杀进程，延后复查
        if Date().timeIntervalSince(lastSpaceChangeDate) < 2.0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.evaluateAppWindows(pid: pid)
            }
            return
        }

        // 1. 优先使用 AX 树进行瞬时非阻塞探测（带 150ms 超时）
        let axCount = axWindows(of: entry.axApp)?.count

        // 核心性能与防误杀：若 AX 确证在活窗口数 > 0，应用正在正常使用，立即取消退出并返回，无需昂贵的 WindowServer IPC 扫描！
        if let ax = axCount, ax > 0 {
            recheckCounts.removeValue(forKey: pid)
            cancelPendingQuitLocked(pid)
            return
        }

        // 补全启动时未建窗应用的 hadWindows 状态：只要检测到曾有窗口，就标记为 hadWindows
        if !entry.hadWindows {
            if (axCount ?? 0) > 0 {
                entry.hadWindows = true
                watched[pid] = entry
            }
            return
        }

        // 2. 仅在 AX 报告无窗或不可用时，才向 WindowServer 发起在屏标准窗口验证
        let wsCount = AutoQuitManager.windowServerStandardWindowCount(for: pid)

        if AutoQuitManager.isConfirmedZeroWindows(pid: pid, axCount: axCount) {
            recheckCounts.removeValue(forKey: pid)
            scheduleQuitLocked(pid, app: entry.app)
        } else if axCount == 0 && (wsCount ?? 0) > 0 {
            // AX 报告无窗但 WindowServer 仍有在屏标准窗口（处于淡出动画或临时图层中），至多重试 2 次微复查，防范无休止轮询
            let attempts = recheckCounts[pid, default: 0]
            if attempts < 2 {
                recheckCounts[pid] = attempts + 1
                if pendingQuits[pid] == nil && !terminatingPids.contains(pid) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                        self?.evaluateAppWindows(pid: pid)
                    }
                }
            } else {
                // 超过 200ms 重试上限，淡出动画必已结束；AX 确证为 0，确认为关窗并调度退出
                recheckCounts.removeValue(forKey: pid)
                scheduleQuitLocked(pid, app: entry.app)
            }
        } else if (axCount ?? 0) > 0 || (wsCount ?? 0) > 0 {
            recheckCounts.removeValue(forKey: pid)
            cancelPendingQuitLocked(pid)
        }
    }

    @objc private func fallbackPoll() {
        assert(Thread.isMainThread)
        guard isRunning else { return }
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        // 性能保护：仅扫描曾经有窗、且不在挂起退出或正在退出流程中的应用
        let candidatePids = watched.keys.filter { pid in
            guard let entry = watched[pid] else { return false }
            return entry.hadWindows && pendingQuits[pid] == nil && !terminatingPids.contains(pid)
        }
        for pid in candidatePids {
            evaluateAppWindowsLocked(pid: pid)
        }
    }

    private func scheduleQuitLocked(_ pid: pid_t, app: NSRunningApplication) {
        guard watched[pid] != nil else { return }
        guard pendingQuits[pid] == nil else { return }
        guard !terminatingPids.contains(pid) else { return }

        let configuredDelay = max(0, min(10, ConfigManager.shared.config.autoQuitDelaySeconds))
        let delaySeconds = Double(configuredDelay)

        let work = DispatchWorkItem { [weak self] in
            self?.executePendingQuit(pid: pid)
        }
        pendingQuits[pid] = work
        if delaySeconds <= 0 {
            DispatchQueue.main.async(execute: work)
            runtimeLog("[AutoQuit] Last window closed for \(app.localizedName ?? "pid \(pid)"); quitting immediately (0s).")
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds, execute: work)
            runtimeLog("[AutoQuit] Last window closed for \(app.localizedName ?? "pid \(pid)"); quitting in \(delaySeconds)s.")
        }
    }

    /// 延迟到期后的复查：窗口确认仍为零、进程对象仍是同一个且未退出、
    /// 开关仍开、名单仍匹配，四个条件都满足才 terminate。
    private func executePendingQuit(pid: pid_t) {
        assert(Thread.isMainThread)
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        pendingQuits[pid] = nil
        guard isRunning, let entry = watched[pid] else { return }
        let app = entry.app
        // pid 槽位可能被新进程复用：必须用持有的 NSRunningApplication 对象做身份验证
        guard !app.isTerminated else { return }
        guard !app.isHidden else { return }
        if Date().timeIntervalSince(lastSpaceChangeDate) < 2.0 {
            runtimeLog("[AutoQuit] Aborted quit for \(app.localizedName ?? "pid \(pid)"): Space transition in progress.")
            return
        }
        let cfg = ConfigManager.shared.config
        guard cfg.enableAutoQuit else { return }
        guard AutoQuitManager.shouldWatch(
            bundleID: app.bundleIdentifier,
            activationPolicy: app.activationPolicy,
            isFinishedLaunching: app.isFinishedLaunching,
            isSelf: app.processIdentifier == ProcessInfo.processInfo.processIdentifier,
            mode: cfg.autoQuitMode,
            rules: cfg.autoQuitAppRules
        ) else { return }
        
        // 双重权威校验复核：AX 与 WindowServer 必须确诊零窗，绝不能误杀仍有窗口的应用
        let axCount = axWindows(of: entry.axApp)?.count
        guard AutoQuitManager.isConfirmedZeroWindows(pid: pid, axCount: axCount) else {
            runtimeLog("[AutoQuit] Aborted quit for \(app.localizedName ?? "pid \(pid)"): windows still present (AX=\(axCount.map(String.init) ?? "nil"), WS=\(AutoQuitManager.windowServerStandardWindowCount(for: pid).map(String.init) ?? "nil")).")
            return
        }

        terminatingPids.insert(pid)
        recheckCounts.removeValue(forKey: pid)
        runtimeLog("[AutoQuit] Terminating \(app.localizedName ?? "pid \(pid)") after last window closed.")
        app.terminate()
    }

    private func cancelPendingQuitLocked(_ pid: pid_t) {
        recheckCounts.removeValue(forKey: pid)
        if let work = pendingQuits.removeValue(forKey: pid) {
            work.cancel()
        }
    }

    private func teardownObserver(_ observer: AXObserver) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    /// 返回 nil 表示 AX 查询失败（状态未知），调用方必须跳过本轮判定；
    /// 只有 `.success` 且能取出数组才返回真实窗口列表。
    private func axWindows(of element: AXUIElement) -> [AXUIElement]? {
        AXUIElementSetMessagingTimeout(element, 0.15)
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)
        guard err == .success else { return nil }
        guard let list = value as? [AXUIElement] else { return nil }
        return list
    }
}
