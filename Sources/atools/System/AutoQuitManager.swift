import Foundation
import AppKit
import ApplicationServices
import Darwin

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

    /// 硬排除的系统应用：退出 Finder 会被 launchd 立即拉起，其余为常驻系统服务与 ATools 自身
    public static let systemExcludedBundleIDs: Set<String> = [
        "com.apple.finder",
        "com.apple.Spotlight",
        "com.apple.notificationcenterui",
        "com.apple.dock",
        "cc.atools.app",
        "cc.atools.app.dev"
    ]

    /// 虚拟机、模拟器与容器平台（基于 AutoQuitQuirks 统一声明式规则库，物理级排除在自动退出之外，防范虚拟机崩溃及未保存数据丢失）
    public static func isProtectedVirtualizationApp(bundleID: String) -> Bool {
        return AutoQuitQuirks.shared.isProtectedVirtualizationApp(bundleID: bundleID)
    }

    private struct WatchedApp {
        let app: NSRunningApplication
        let axApp: AXUIElement
        let observer: AXObserver
        /// 已注册销毁通知的窗口元素，用于窗口新建时去重注册。
        var registeredWindowRefs: [AXUIElement]
        /// 最近一次确认时是否拥有窗口。零窗口应用（登录项、后台 utility）绝不直接
        /// 退出，只有从「有窗」跌落到「确认零窗」才调度退出。
        var hadWindows: Bool
        /// 最近一次处于前台激活态的时间戳，用于防止失焦切后台时的瞬态误杀
        var lastActiveDate: Date
        /// 最近一次收到窗口关闭/销毁事件的时间戳
        var lastCloseEventDate: Date
    }

    private var watched: [pid_t: WatchedApp] = [:]
    private var pendingQuits: [pid_t: DispatchWorkItem] = [:]
    private var pendingRechecks: [pid_t: DispatchWorkItem] = [:]
    private var terminatingPids: Set<pid_t> = []
    private var recheckCounts: [pid_t: Int] = [:]
    private var fallbackTimer: Timer?
    private var isRunning = false
    private var lock = os_unfair_lock()
    private var lastSpaceChangeDate: Date = .distantPast
    private var suppressedPids: Set<pid_t> = []

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
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self, self.isRunning,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.handleAppActivated(app)
        })
        // 关键防御：监听应用失焦/切换应用，更新失焦时间戳，防止切后台过渡期误杀
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self, self.isRunning,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.handleAppDeactivated(app)
        })
        // 监听虚拟桌面 (Spaces) 切换：Space 切换时 WindowServer 与 AX 处于过渡态，设立保护宽限期防止误杀
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.lastSpaceChangeDate = Date()
        })
        // 监听系统即将休眠：立刻清空排队退出的计时任务，防止睡眠中产生定时器竞争与误杀
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.cancelAllPendingTasks()
        })
        // 睡眠唤醒后其他应用的 AX 树可能整体失效，防抖延时 1.0s 等待系统及所有应用恢复在屏窗口后安全重建
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self, self.isRunning else { return }
                self.rebuild()
            }
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
        guard !isProtectedVirtualizationApp(bundleID: bid) else { return false }
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

    /// WindowServer 层面标准应用窗口计数（Layer 0...15，纯几何公开信息，零隐私与录屏权限要求，结合 AutoQuitQuirks 规则清洗离屏幽灵）
    public static func windowServerStandardWindowCount(for pid: pid_t, bundleID: String? = nil) -> Int? {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let quirks = AutoQuitQuirks.shared
        let resolvedBundleID = bundleID ?? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier

        var count = 0
        for w in list {
            guard let ownerPID = w[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else { continue }
            // 限制在标准业务窗体层级（Layer 0 普通窗口，Layer 3/8 浮动面板与模态对话框）
            guard let layer = w[kCGWindowLayer as String] as? Int, (0...15).contains(layer) else { continue }
            guard let alpha = w[kCGWindowAlpha as String] as? Double, alpha > 0.01 else { continue }
            guard let bounds = w[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double,
                  width > 40, height > 40 else { continue }

            let ownerName = (w[kCGWindowOwnerName as String] as? String) ?? ""
            let rawName = (w[kCGWindowName as String] as? String) ?? ""
            let isOnScreen = (w[kCGWindowIsOnscreen as String] as? Bool) ?? false

            // 核心清洗：利用 AutoQuitQuirks 识别系统代理、CEF 缓冲、orderOut 离屏底板
            if quirks.isGhostWindow(
                bundleID: resolvedBundleID,
                ownerName: ownerName,
                title: rawName,
                width: width,
                height: height,
                isOnScreen: isOnScreen
            ) {
                continue
            }

            if isOnScreen {
                // 当前屏幕可见的标准在屏业务窗口（包括处于关闭淡出动画中或 AX 尚未同步的实体窗口）
                if width > 120 && height > 90 || !rawName.isEmpty {
                    count += 1
                }
            }
        }
        return count
    }

    /// 实例级别零窗确认：结合当前进程的 AX 查询与 WindowServer 计数
    public static func isConfirmedZeroWindows(pid: pid_t, axCount: Int?, bundleID: String? = nil) -> Bool {
        let wsCount = windowServerStandardWindowCount(for: pid, bundleID: bundleID)
        return isConfirmedZeroWindowCount(axCount: axCount, windowServerCount: wsCount)
    }

    /// 当 LaunchServices 刚启动应用或沙盒映射未就绪时，app.processIdentifier 可能短暂返回 -1。
    /// 通过 libproc proc_listpids + proc_pidpath 极速在内核中根据可执行文件路径或 Bundle 路径反查真实 PID
    public static func resolveProcessIdentifier(for app: NSRunningApplication) -> pid_t? {
        let pid = app.processIdentifier
        if pid > 0 { return pid }

        if let targetPath = app.executableURL?.path ?? app.bundleURL?.path {
            var pids = [pid_t](repeating: 0, count: 2048)
            let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(MemoryLayout<pid_t>.size * pids.count))
            let count = Int(bytes) / MemoryLayout<pid_t>.size
            var pathBuffer = [CChar](repeating: 0, count: 4096)
            for i in 0..<count {
                let p = pids[i]
                guard p > 0, p != ProcessInfo.processInfo.processIdentifier else { continue }
                let len = proc_pidpath(p, &pathBuffer, UInt32(pathBuffer.count))
                if len > 0 {
                    let path = String(cString: pathBuffer)
                    if path == targetPath || path.hasPrefix(targetPath) {
                        return p
                    }
                }
            }
        }
        return nil
    }

    private func shouldAttach(_ app: NSRunningApplication) -> Bool {
        let cfg = ConfigManager.shared.config
        let resolvedPid = AutoQuitManager.resolveProcessIdentifier(for: app) ?? app.processIdentifier
        return AutoQuitManager.shouldWatch(
            bundleID: app.bundleIdentifier,
            activationPolicy: app.activationPolicy,
            isFinishedLaunching: app.isFinishedLaunching,
            isSelf: resolvedPid == ProcessInfo.processInfo.processIdentifier,
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
        // 每 1.0s 一次轻量查询，兼顾即时性与低功耗。
        let timer = Timer(timeInterval: 1.0, target: self, selector: #selector(fallbackPoll), userInfo: nil, repeats: true)
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
        for work in pendingRechecks.values {
            work.cancel()
        }
        pendingRechecks.removeAll()
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

    private func handleAppActivated(_ app: NSRunningApplication) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard let pid = AutoQuitManager.resolveProcessIdentifier(for: app), pid > 0 else {
            attachLocked(app)
            return
        }
        if watched[pid] == nil {
            attachLocked(app)
        } else if var entry = watched[pid] {
            entry.lastActiveDate = Date()
            let axCount = axWindows(of: entry.axApp)?.count
            let wsCount = AutoQuitManager.windowServerStandardWindowCount(for: pid)
            if (axCount ?? 0) > 0 || (wsCount ?? 0) > 0 {
                entry.hadWindows = true
                if let list = axWindows(of: entry.axApp) {
                    for window in list {
                        if !entry.registeredWindowRefs.contains(where: { CFEqual($0, window) }) {
                            if AXObserverAddNotification(entry.observer, window, kAXUIElementDestroyedNotification as CFString, nil) == .success {
                                entry.registeredWindowRefs.append(window)
                            }
                        }
                    }
                }
            }
            watched[pid] = entry
        }
    }

    private func handleAppDeactivated(_ app: NSRunningApplication) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard let pid = AutoQuitManager.resolveProcessIdentifier(for: app), pid > 0 else { return }
        if var entry = watched[pid] {
            entry.lastActiveDate = Date()
            watched[pid] = entry
            // 关键安全防御：切走应用（失焦）说明用户正在切换应用/切换工作上下文，而不是主动关窗！
            // 立即撤销失焦瞬间因瞬态波动可能发起的退出调度与复查任务！
            cancelPendingQuitLocked(pid)
            cancelPendingRecheckLocked(pid)
        }
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
        guard let pid = AutoQuitManager.resolveProcessIdentifier(for: app), pid > 0 else {
            // 若应用处于极早期启动阶段，PID 尚未由系统注册完毕，防抖延迟 0.4s 重新挂载
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.attachIfEligible(app)
            }
            return
        }
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
            hadWindows: false,
            lastActiveDate: app.isActive ? Date() : .distantPast,
            lastCloseEventDate: .distantPast
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
            cancelPendingRecheckLocked(pid)
            // 新窗口：注册其销毁通知；若窗口重新出现，取消挂起的退出
            if !entry.registeredWindowRefs.contains(where: { CFEqual($0, element) }) {
                if AXObserverAddNotification(entry.observer, element, kAXUIElementDestroyedNotification as CFString, nil) == .success {
                    entry.registeredWindowRefs.append(element)
                }
            }
            let axCount = axWindows(of: entry.axApp)?.count
            let wsCount = AutoQuitManager.windowServerStandardWindowCount(for: pid)
            if (axCount ?? 0) > 0 || (wsCount ?? 0) > 0 || isStandardBusinessWindow(element) {
                entry.hadWindows = true
                watched[pid] = entry
                cancelPendingQuitLocked(pid)
            }
        } else if notificationName == (kAXWindowClosedNotification as String)
                    || notificationName == (kAXUIElementDestroyedNotification as String) {
            let isKnownWindow = entry.registeredWindowRefs.contains(where: { CFEqual($0, element) })

            // 关键安全防御：对于 kAXUIElementDestroyedNotification，通常必须属于已注册的标准业务窗口；
            // 针对 WPS / CEF 等失焦重置 AX 树的应用，若当前正处于前台激活态（app.isActive）
            // 且 registeredWindowRefs 因早期失焦为空，允许作为关窗候选处理并执行严谨求值
            if notificationName == (kAXUIElementDestroyedNotification as String) && !isKnownWindow {
                if !entry.app.isActive || !entry.registeredWindowRefs.isEmpty {
                    return
                }
            }

            // 确认为窗口销毁，从已注册窗口列表中移除该窗口引用
            entry.registeredWindowRefs.removeAll(where: { CFEqual($0, element) })
            entry.lastCloseEventDate = Date()
            if !entry.hadWindows {
                if notificationName == (kAXWindowClosedNotification as String) || isKnownWindow {
                    entry.hadWindows = true
                }
            }
            watched[pid] = entry
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

        // 安全防护 2：Space 虚拟桌面切换过渡期内（2秒内）冻结零窗杀进程，撤销退出调度
        if Date().timeIntervalSince(lastSpaceChangeDate) < 2.0 {
            cancelPendingQuitLocked(pid)
            cancelPendingRecheckLocked(pid)
            return
        }

        // 安全防护 3：应用刚失焦切换到后台的过渡期（2.0 秒内）冻结零窗杀进程
        // 切应用瞬间窗口层级与 AX 状态发生剧烈翻转，且可能伴随输入法/Tooltip 等微小辅助元素销毁，绝不能借机发起退出调度
        if !app.isActive && Date().timeIntervalSince(entry.lastActiveDate) < 2.0 {
            cancelPendingQuitLocked(pid)
            cancelPendingRecheckLocked(pid)
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
        let wsCount = AutoQuitManager.windowServerStandardWindowCount(for: pid, bundleID: app.bundleIdentifier)

        if AutoQuitManager.isConfirmedZeroWindows(pid: pid, axCount: axCount, bundleID: app.bundleIdentifier) {
            recheckCounts.removeValue(forKey: pid)
            cancelPendingRecheckLocked(pid)
            scheduleQuitLocked(pid, app: entry.app)
        } else if axCount == 0 && (wsCount ?? 0) > 0 {
            // 防重入保护：点击红叉时 AXWindowClosed 与 AXUIElementDestroyed 往往在同一毫秒并发到达；
            // 若当前已有排队中的延迟复查任务，直接合并忽略，防止同一帧内把 recheckCounts 配额瞬间耗尽。
            guard pendingRechecks[pid] == nil else { return }

            // AX 报告无窗但 WindowServer 仍有在屏标准窗口（处于 250ms~350ms 淡出关闭动画或临时图层中），
            // 至多重试 5 次（每次间隔 0.12s，共覆盖 600ms 关闭动画窗口期），防范无休止轮询同时确保关闭动画结束后准确触发退出。
            let attempts = recheckCounts[pid, default: 0]
            if attempts < 5 {
                recheckCounts[pid] = attempts + 1
                if pendingQuits[pid] == nil && !terminatingPids.contains(pid) {
                    let work = DispatchWorkItem { [weak self] in
                        guard let self = self else { return }
                        os_unfair_lock_lock(&self.lock)
                        self.pendingRechecks.removeValue(forKey: pid)
                        os_unfair_lock_unlock(&self.lock)
                        self.evaluateAppWindows(pid: pid)
                    }
                    pendingRechecks[pid] = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
                }
            } else {
                // 超过重试上限（600ms）后，WindowServer 依然确证存在在屏标准窗口！这证明该窗口真实存在且未被用户关闭！
                // 绝对不能退出！清除重试计数并撤销退出调度，安全保护后台运行或失焦的应用。
                recheckCounts.removeValue(forKey: pid)
                cancelPendingQuitLocked(pid)
                AutoQuitDecisionTrace.shared.record(
                    pid: pid,
                    bundleID: app.bundleIdentifier ?? "",
                    appName: app.localizedName ?? "",
                    axWindowCount: axCount,
                    wsWindowCount: wsCount,
                    decision: .aborted,
                    reasonCode: "WindowServerConfirmedOnscreen",
                    detail: "防抖期后 WindowServer 仍有在屏实体窗口"
                )
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

        // 自愈轮询：定期扫描 runningApplications，确保任何漏网之鱼（如早先 PID=-1 挂载失败的应用）能自动补全监视
        for app in NSWorkspace.shared.runningApplications {
            if let pid = AutoQuitManager.resolveProcessIdentifier(for: app), pid > 0 {
                if watched[pid] == nil && shouldAttach(app) {
                    attachLocked(app)
                }
            }
        }
        
        let now = Date()
        let pids = Array(watched.keys)
        for pid in pids {
            guard var entry = watched[pid],
                  pendingQuits[pid] == nil,
                  pendingRechecks[pid] == nil,
                  !terminatingPids.contains(pid) else { continue }
            if !entry.hadWindows {
                let axCount = axWindows(of: entry.axApp)?.count
                let wsCount = AutoQuitManager.windowServerStandardWindowCount(for: pid, bundleID: entry.app.bundleIdentifier)
                if (axCount ?? 0) > 0 || (wsCount ?? 0) > 0 {
                    entry.hadWindows = true
                    if let list = axWindows(of: entry.axApp) {
                        for window in list {
                            if !entry.registeredWindowRefs.contains(where: { CFEqual($0, window) }) {
                                if AXObserverAddNotification(entry.observer, window, kAXUIElementDestroyedNotification as CFString, nil) == .success {
                                    entry.registeredWindowRefs.append(window)
                                }
                            }
                        }
                    }
                    watched[pid] = entry
                }
            } else {
                // 核心生命周期防御：兜底轮询绝不能在后台对稳定运行、未发生关窗事件的应用进行“零窗误杀”！
                // 只有当应用当前处于前台活跃状态（app.isActive）或者最近 3.0 秒内接收到过明确的关窗销毁事件时，才触发求值！
                let isActive = entry.app.isActive
                let recentlyHadCloseEvent = now.timeIntervalSince(entry.lastCloseEventDate) < 3.0

                if isActive || recentlyHadCloseEvent {
                    evaluateAppWindowsLocked(pid: pid)
                }
            }
        }
    }

    private func scheduleQuitLocked(_ pid: pid_t, app: NSRunningApplication) {
        guard watched[pid] != nil else { return }
        guard pendingQuits[pid] == nil else { return }
        guard !terminatingPids.contains(pid) else { return }

        // 若本轮会话中用户已点击取消退出，抑制对该应用的自动退出，直至重新激活开窗
        if suppressedPids.contains(pid) {
            AutoQuitDecisionTrace.shared.record(
                pid: pid,
                bundleID: app.bundleIdentifier ?? "",
                appName: app.localizedName ?? "pid \(pid)",
                axWindowCount: 0,
                wsWindowCount: 0,
                decision: .aborted,
                reasonCode: "UserSuppressedInCurrentSession",
                detail: "用户曾点击取消，本轮会话静默豁免"
            )
            return
        }

        // 前台确诊零窗时的主动时序加固：刷新最后关窗时间戳，确保延迟退出期间即使失焦也能顺利终审
        if app.isActive, var entry = watched[pid] {
            entry.lastCloseEventDate = Date()
            watched[pid] = entry
        }

        let configuredDelay = max(0, min(10, ConfigManager.shared.config.autoQuitDelaySeconds))
        let delaySeconds = Double(configuredDelay)

        let work = DispatchWorkItem { [weak self] in
            self?.executePendingQuit(pid: pid)
        }
        pendingQuits[pid] = work

        AutoQuitDecisionTrace.shared.record(
            pid: pid,
            bundleID: app.bundleIdentifier ?? "",
            appName: app.localizedName ?? "pid \(pid)",
            axWindowCount: 0,
            wsWindowCount: 0,
            decision: .quitScheduled,
            reasonCode: "ConfirmedZeroWindows",
            detail: "计划延迟 \(delaySeconds)s 后执行退出"
        )

        if delaySeconds <= 0 {
            DispatchQueue.main.async(execute: work)
            runtimeLog("[AutoQuit] Last window closed for \(app.localizedName ?? "pid \(pid)"); quitting immediately (0s).")
        } else {
            // 展示可撤销 HUD 浮层（需配置开启）
            if ConfigManager.shared.config.enableAutoQuitUndoHUD {
                AutoQuitUndoHUDController.shared.showCountdown(for: app, seconds: delaySeconds) { [weak self] cancelledPid in
                    guard let self = self else { return }
                    os_unfair_lock_lock(&self.lock)
                    self.cancelPendingQuitLocked(cancelledPid)
                    self.suppressedPids.insert(cancelledPid)
                    os_unfair_lock_unlock(&self.lock)
                    AutoQuitDecisionTrace.shared.record(
                        pid: cancelledPid,
                        bundleID: app.bundleIdentifier ?? "",
                        appName: app.localizedName ?? "pid \(cancelledPid)",
                        axWindowCount: 0,
                        wsWindowCount: 0,
                        decision: .aborted,
                        reasonCode: "UserCancelledViaUndoHUD",
                        detail: "用户在 HUD 上点击了取消"
                    )
                }
            }
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

        AutoQuitUndoHUDController.shared.dismiss()
        pendingQuits[pid] = nil
        guard isRunning, let entry = watched[pid] else { return }
        let app = entry.app
        // pid 槽位可能被新进程复用：必须用持有的 NSRunningApplication 对象做身份验证
        guard !app.isTerminated else { return }
        guard !app.isHidden else { return }

        // 关键安全防御 1：若应用已重新变为活跃状态且拥有窗口，绝对不能退出
        if app.isActive {
            let axCount = axWindows(of: entry.axApp)?.count
            let wsCount = AutoQuitManager.windowServerStandardWindowCount(for: pid, bundleID: app.bundleIdentifier)
            if (axCount ?? 0) > 0 || (wsCount ?? 0) > 0 {
                runtimeLog("[AutoQuit] Aborted quit for \(app.localizedName ?? "pid \(pid)"): app is active and has window.")
                AutoQuitDecisionTrace.shared.record(
                    pid: pid,
                    bundleID: app.bundleIdentifier ?? "",
                    appName: app.localizedName ?? "",
                    axWindowCount: axCount,
                    wsWindowCount: wsCount,
                    decision: .aborted,
                    reasonCode: "AppBecameActiveWithWindow"
                )
                return
            }
        }

        // 关键安全防御 2：检查是否有任何已最小化的窗口（Minimized in Dock），最小化绝不是关闭！
        if let windows = axWindows(of: entry.axApp) {
            let hasMinimized = windows.contains { w in
                var minVal: CFTypeRef?
                AXUIElementCopyAttributeValue(w, kAXMinimizedAttribute as CFString, &minVal)
                return (minVal as? Bool) == true
            }
            if hasMinimized {
                runtimeLog("[AutoQuit] Aborted quit for \(app.localizedName ?? "pid \(pid)"): has minimized window in Dock.")
                AutoQuitDecisionTrace.shared.record(
                    pid: pid,
                    bundleID: app.bundleIdentifier ?? "",
                    appName: app.localizedName ?? "",
                    axWindowCount: windows.count,
                    wsWindowCount: nil,
                    decision: .aborted,
                    reasonCode: "HasMinimizedWindowInDock"
                )
                return
            }
        }

        if Date().timeIntervalSince(lastSpaceChangeDate) < 2.0 {
            runtimeLog("[AutoQuit] Aborted quit for \(app.localizedName ?? "pid \(pid)"): Space transition in progress.")
            AutoQuitDecisionTrace.shared.record(
                pid: pid,
                bundleID: app.bundleIdentifier ?? "",
                appName: app.localizedName ?? "",
                axWindowCount: nil,
                wsWindowCount: nil,
                decision: .aborted,
                reasonCode: "SpaceTransitionGracePeriod"
            )
            return
        }

        // 关键安全防御 3：若应用当前处于失焦/后台状态，且失焦过渡期或近期无前台主动关窗，坚决放弃退出
        if !app.isActive {
            let sinceActive = Date().timeIntervalSince(entry.lastActiveDate)
            let sinceClose = Date().timeIntervalSince(entry.lastCloseEventDate)
            // 如果刚切到后台不久（< 2.5s），或者最近根本没有收到过明确的窗口销毁事件（>= 3.0s），坚决放弃
            if sinceActive < 2.5 || sinceClose >= 3.0 {
                runtimeLog("[AutoQuit] Aborted quit for \(app.localizedName ?? "pid \(pid)"): app is in background (sinceActive=\(String(format: "%.1f", sinceActive))s, sinceClose=\(String(format: "%.1f", sinceClose))s).")
                AutoQuitDecisionTrace.shared.record(
                    pid: pid,
                    bundleID: app.bundleIdentifier ?? "",
                    appName: app.localizedName ?? "",
                    axWindowCount: nil,
                    wsWindowCount: nil,
                    decision: .aborted,
                    reasonCode: "BackgroundDeactivatedGracePeriod"
                )
                return
            }
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
        guard AutoQuitManager.isConfirmedZeroWindows(pid: pid, axCount: axCount, bundleID: app.bundleIdentifier) else {
            let wsCount = AutoQuitManager.windowServerStandardWindowCount(for: pid, bundleID: app.bundleIdentifier)
            runtimeLog("[AutoQuit] Aborted quit for \(app.localizedName ?? "pid \(pid)"): windows still present (AX=\(axCount.map(String.init) ?? "nil"), WS=\(wsCount.map(String.init) ?? "nil")).")
            AutoQuitDecisionTrace.shared.record(
                pid: pid,
                bundleID: app.bundleIdentifier ?? "",
                appName: app.localizedName ?? "",
                axWindowCount: axCount,
                wsWindowCount: wsCount,
                decision: .aborted,
                reasonCode: "WindowsStillPresentOnFinalCheck"
            )
            return
        }

        terminatingPids.insert(pid)
        recheckCounts.removeValue(forKey: pid)
        cancelPendingRecheckLocked(pid)
        AutoQuitDecisionTrace.shared.record(
            pid: pid,
            bundleID: app.bundleIdentifier ?? "",
            appName: app.localizedName ?? "pid \(pid)",
            axWindowCount: 0,
            wsWindowCount: 0,
            decision: .quitExecuted,
            reasonCode: "ConfirmedAndTerminated"
        )
        runtimeLog("[AutoQuit] Terminating \(app.localizedName ?? "pid \(pid)") after last window closed.")
        app.terminate()
    }

    private func cancelPendingRecheckLocked(_ pid: pid_t) {
        if let work = pendingRechecks.removeValue(forKey: pid) {
            work.cancel()
        }
    }

    private func cancelAllPendingTasks() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        for work in pendingQuits.values { work.cancel() }
        pendingQuits.removeAll()
        for work in pendingRechecks.values { work.cancel() }
        pendingRechecks.removeAll()
        recheckCounts.removeAll()
        AutoQuitUndoHUDController.shared.dismiss()
    }

    private func cancelPendingQuitLocked(_ pid: pid_t) {
        recheckCounts.removeValue(forKey: pid)
        cancelPendingRecheckLocked(pid)
        if let work = pendingQuits.removeValue(forKey: pid) {
            work.cancel()
            AutoQuitUndoHUDController.shared.dismiss()
        }
    }

    private func teardownObserver(_ observer: AXObserver) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    /// 返回 nil 表示 AX 查询失败（状态未知），调用方必须跳过本轮判定；
    /// 只有成功查询且确知窗口状态才返回窗口列表。
    private func axWindows(of element: AXUIElement) -> [AXUIElement]? {
        AXUIElementSetMessagingTimeout(element, 0.15)
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)
        var result: [AXUIElement] = (err == .success ? (value as? [AXUIElement] ?? []) : [])

        // 关键防御：某些应用（如 WPS Office、部分 Qt/CEF 应用）失焦或置于后台时，
        // 其 kAXWindowsAttribute 可能暂时返回空数组，但其 kAXMainWindowAttribute 或 kAXFocusedWindowAttribute 仍真实在活。
        // 注意：仅当 WindowServer 确证仍有在屏标准窗口时才探测，彻底防止关窗后 AppKit 内部尚未置空的残留主窗体对象被误判为“仍有窗口”而阻断退出
        if result.isEmpty {
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            let wsCount = (pid > 0) ? AutoQuitManager.windowServerStandardWindowCount(for: pid) : nil
            if (wsCount ?? 0) > 0 {
                for attr in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
                    var winVal: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, attr as CFString, &winVal) == .success, let win = winVal {
                        let winEl = win as! AXUIElement
                        var roleVal: CFTypeRef?
                        if AXUIElementCopyAttributeValue(winEl, kAXRoleAttribute as CFString, &roleVal) == .success,
                           (roleVal as? String) == "AXWindow" {
                            if !result.contains(where: { CFEqual($0, winEl) }) {
                                result.append(winEl)
                            }
                        }
                    }
                }
            }
        }

        // 部分原生 Cocoa 应用（如 TextEdit）在最后一个窗口或打开面板关闭后，kAXWindowsAttribute 可能返回 .noValue；
        // 若其应用级 AXRole 仍正常响应，说明 AX 服务在线且当前确无窗口，应视为空窗口列表 [] 而非查询失败 nil。
        if err == .noValue && result.isEmpty {
            var appRole: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &appRole) == .success {
                return []
            }
        }

        if err != .success && result.isEmpty {
            return nil
        }
        // 关键过滤：排除桌面常驻小挂件（如百度网盘 200x80 桌面传输挂件、迅雷悬浮球等），
        // 仅将具备关闭/最小化按钮、或模态对话框、或达到主业务窗口尺寸底线（> 320x200）的窗口作为有效在活窗口。
        return result.filter { isStandardBusinessWindow($0) }
    }

    /// 判断是否为用户可操作/可关闭的主业务窗口或对话框，
    /// 排除百度网盘悬浮窗、迅雷悬浮球等常驻桌面但无红绿灯控制按钮的小挂件。
    private func isStandardBusinessWindow(_ w: AXUIElement) -> Bool {
        var sizeVal: CFTypeRef?
        var size: CGSize = .zero
        if AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &sizeVal) == .success, let s = sizeVal {
            _ = AXValueGetValue(s as! AXValue, .cgSize, &size)
        }

        // 核心安全底线：过滤微型图标/常驻悬浮挂件（如夸克 40x40 桌面悬浮球、百度网盘 200x80 挂件、迅雷悬浮球）
        // 任何真实的主业务窗口或系统模态对话框尺寸均不会小于 160x90
        if size != .zero && (size.width < 160 || size.height < 90) {
            return false
        }

        var closeVal: CFTypeRef?
        let hasClose = (AXUIElementCopyAttributeValue(w, kAXCloseButtonAttribute as CFString, &closeVal) == .success && closeVal != nil)
        var minVal: CFTypeRef?
        let hasMin = (AXUIElementCopyAttributeValue(w, kAXMinimizeButtonAttribute as CFString, &minVal) == .success && minVal != nil)
        if hasClose || hasMin {
            return true
        }

        var subroleVal: CFTypeRef?
        AXUIElementCopyAttributeValue(w, kAXSubroleAttribute as CFString, &subroleVal)
        let subrole = (subroleVal as? String) ?? ""
        if subrole == "AXDialog" || subrole == "AXSystemDialog" || subrole == "AXSheet" {
            return true
        }

        var modalVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(w, "AXModal" as CFString, &modalVal) == .success, (modalVal as? Bool) == true {
            return true
        }

        if size.width > 320 && size.height > 200 {
            return true
        }

        return false
    }

    // MARK: - 诊断快照

    /// 获取当前监视中的活跃应用快照（供 AutoQuitInspectorSheet 查看与排障审计）
    public func currentWatchedAppsSnapshot() -> [(name: String, bundleID: String, pid: pid_t, axCount: String, wsCount: String, rule: String)] {
        assert(Thread.isMainThread)
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        var result: [(name: String, bundleID: String, pid: pid_t, axCount: String, wsCount: String, rule: String)] = []
        for (pid, entry) in watched {
            let name = entry.app.localizedName ?? "应用"
            let bid = entry.app.bundleIdentifier ?? "-"
            let ax = axWindows(of: entry.axApp).map { String($0.count) } ?? "err"
            let ws = AutoQuitManager.windowServerStandardWindowCount(for: pid, bundleID: bid).map(String.init) ?? "-"
            let rule = AutoQuitQuirks.shared.matchRule(bundleID: bid, ownerName: name)?.name ?? "通用标准"
            result.append((name: name, bundleID: bid, pid: pid, axCount: ax, wsCount: ws, rule: rule))
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
