import Foundation
import AppKit
import ApplicationServices

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
    private static let systemExcludedBundleIDs: Set<String> = [
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
    private var fallbackTimer: Timer?
    private var isRunning = false
    private var lock = os_unfair_lock()

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
        startIfEnabled()
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
        case .allApps: return !rules.contains(bid)
        case .onlyListed: return rules.contains(bid)
        }
    }

    /// 零窗判定（纯函数）：AX 查询失败（nil）绝不能视为零窗，否则 AX 树失效的
    /// 应用会在「最后一个窗口关闭」前就被误杀。
    public static func isConfirmedZeroWindowCount(_ count: Int?) -> Bool {
        return count == 0
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

        // 兜底轮询：捕获不吐 AX 销毁事件的应用（部分 Electron/Java）。
        // 仅扫 hadWindows 的应用，每 4s 一次 AX 查询，代价可忽略。
        let timer = Timer(timeInterval: 4.0, target: self, selector: #selector(fallbackPoll), userInfo: nil, repeats: true)
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
        let addErr = AXObserverAddNotification(obs, axApp, kAXWindowCreatedNotification as CFString, nil)
        if addErr != .success {
            runtimeLog("[AutoQuit] AddNotification(WindowCreated) failed for pid \(pid): error \(addErr.rawValue)")
        }

        var entry = WatchedApp(
            app: app,
            axApp: axApp,
            observer: obs,
            registeredWindowRefs: [],
            hadWindows: false
        )
        // 为现有窗口注册销毁通知；初始窗口数决定 hadWindows（零窗口应用绝不直接退出）
        let existing = axWindows(of: axApp)
        if let list = existing {
            entry.hadWindows = !list.isEmpty
            for window in list {
                if AXObserverAddNotification(obs, window, kAXUIElementDestroyedNotification as CFString, nil) == .success {
                    entry.registeredWindowRefs.append(window)
                }
            }
        }
        watched[pid] = entry
        let knownCount = existing.map { String($0.count) } ?? "unknown"
        runtimeLog("[AutoQuit] Watching \(app.localizedName ?? "pid \(pid)") (windows: \(knownCount))")
    }

    func handleAXNotification(pid: pid_t, element: AXUIElement, notificationName: String) {
        assert(Thread.isMainThread)
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        guard isRunning, var entry = watched[pid] else { return }

        if notificationName == kAXWindowCreatedNotification as String {
            // 新窗口：注册其销毁通知；若窗口重新出现，取消挂起的退出
            if !entry.registeredWindowRefs.contains(where: { CFEqual($0, element) }) {
                if AXObserverAddNotification(entry.observer, element, kAXUIElementDestroyedNotification as CFString, nil) == .success {
                    entry.registeredWindowRefs.append(element)
                }
            }
            if let count = axWindows(of: entry.axApp)?.count, count > 0 {
                entry.hadWindows = true
                watched[pid] = entry
                cancelPendingQuitLocked(pid)
            }
        } else if notificationName == kAXUIElementDestroyedNotification as String {
            guard entry.hadWindows else { return }
            let count = axWindows(of: entry.axApp)?.count
            if AutoQuitManager.isConfirmedZeroWindowCount(count) {
                scheduleQuitLocked(pid, app: entry.app)
            } else if let c = count, c > 0 {
                cancelPendingQuitLocked(pid)
            }
            // count == nil → AX 状态未知，跳过本轮判定
        }
    }

    @objc private func fallbackPoll() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        guard isRunning else { return }
        for (pid, entry) in watched where entry.hadWindows {
            let count = axWindows(of: entry.axApp)?.count
            if AutoQuitManager.isConfirmedZeroWindowCount(count) {
                scheduleQuitLocked(pid, app: entry.app)
            } else if let c = count, c > 0 {
                cancelPendingQuitLocked(pid)
            }
        }
    }

    private func scheduleQuitLocked(_ pid: pid_t, app: NSRunningApplication) {
        guard watched[pid] != nil else { return }
        guard pendingQuits[pid] == nil else { return }

        let delay = max(0, min(10, ConfigManager.shared.config.autoQuitDelaySeconds))
        let work = DispatchWorkItem { [weak self] in
            self?.executePendingQuit(pid: pid)
        }
        pendingQuits[pid] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay), execute: work)
        runtimeLog("[AutoQuit] Last window closed for \(app.localizedName ?? "pid \(pid)"); quitting in \(delay)s.")
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
        guard AutoQuitManager.isConfirmedZeroWindowCount(axWindows(of: entry.axApp)?.count) else { return }

        runtimeLog("[AutoQuit] Terminating \(app.localizedName ?? "pid \(pid)") after last window closed.")
        app.terminate()
    }

    private func cancelPendingQuitLocked(_ pid: pid_t) {
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
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)
        guard err == .success else { return nil }
        guard let list = value as? [AXUIElement] else { return nil }
        return list
    }
}
