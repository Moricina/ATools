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
        /// 针对无法注册应用级 AXObserver 通知（如 WPS 报错 -25204）的架构降级标记
        var isAXObserverDegraded: Bool
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
    /// Y-02: 后台异步探测队列，避免在持有锁或主线程定时器中长时间阻塞于无响应第三方应用的 AX IPC
    private let probeQueue = DispatchQueue(label: "cc.atools.autoquit.probe", qos: .utility)
    private var isFallbackProbeInFlight = false

    private var defaultCenterObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    private init() {
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
            let resolvedPid = AutoQuitManager.resolveProcessIdentifier(for: app) ?? app.processIdentifier
            self.detach(pid: resolvedPid)
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
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self = self, self.isRunning,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.handleAppDeactivated(app)
        })
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.lastSpaceChangeDate = Date()
        })
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.cancelAllPendingTasks()
        })
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

    public func reloadIfTrusted() {
        assert(Thread.isMainThread)
        let wasRunning = isRunning
        startIfEnabled()
        if isRunning != wasRunning {
            NotificationCenter.default.post(name: .atoolsAutoQuitDidChange, object: nil)
        }
    }

    public func updateConfiguration() {
        assert(Thread.isMainThread)
        rebuild()
    }

    private func rebuild() {
        stop()
        startIfEnabled()
    }

    // MARK: - 监视资格（纯函数，供 --test 直接断言，不触碰单例状态）

    public static func shouldWatch(
        bundleID: String?,
        activationPolicy: NSApplication.ActivationPolicy,
        isFinishedLaunching: Bool,
        isSelf: Bool,
        mode: AutoQuitMode,
        rules: [String]
    ) -> Bool {
        guard !isSelf else { return false }
        guard isFinishedLaunching else { return false }
        guard let bid = bundleID, !bid.isEmpty else { return false }
        guard !systemExcludedBundleIDs.contains(bid) else { return false }
        guard !isProtectedVirtualizationApp(bundleID: bid) else { return false }
        switch mode {
        case .allApps:
            guard activationPolicy == .regular else { return false }
            return !rules.contains(where: { $0.caseInsensitiveCompare(bid) == .orderedSame })
        case .onlyListed:
            return rules.contains(where: { $0.caseInsensitiveCompare(bid) == .orderedSame })
        }
    }

    /// 零窗判定（纯函数）：AX 查询失败（nil）绝不能视为零窗
    public static func isConfirmedZeroWindowCount(_ count: Int?) -> Bool {
        return count == 0
    }

    /// Y-01: 双重权威校验纯函数：唯有当 AX 窗口计数与 WindowServer 真实窗口层双方均明确返回 0 时，才确诊为零窗。
    /// 若任一方返回 nil（查询超时/状态未知）或 > 0，一律返回 false（Fail-Safe 防误杀）。
    public static func isConfirmedZeroWindowCount(axCount: Int?, windowServerCount: Int?) -> Bool {
        guard let ax = axCount, let ws = windowServerCount else {
            return false
        }
        return ax == 0 && ws == 0
    }

    /// 判断单个 WindowServer 窗口是否符合标准有效业务窗口（纯函数，供 windowServerStandardWindowCount 与单元测试共用）
    public static func isStandardWindowCandidate(
        bundleID: String?,
        ownerName: String?,
        rawName: String,
        width: Double,
        height: Double,
        isOnScreen: Bool
    ) -> Bool {
        let quirks = AutoQuitQuirks.shared
        if quirks.isGhostWindow(
            bundleID: bundleID,
            ownerName: ownerName,
            title: rawName,
            width: width,
            height: height,
            isOnScreen: isOnScreen
        ) {
            return false
        }

        if isOnScreen {
            return (width > 120 && height > 70) || !rawName.isEmpty
        } else {
            // 军师审定方案：离屏窗口 (isOnScreen == false) 必须已通过 isGhostWindow 清洗
            // 1. 特征 A（有明确业务标题）：非空标题且尺寸达到常规视窗 (width > 120 && height > 70)，
            //    排除极小微元，认定为位于其他 Space、最小化或被遮挡的实体业务窗口；
            // 2. 特征 B（Chromium 无标题大视窗）：Chromium 多进程架构下部分离屏主窗口标题为空，
            //    必须满足主视窗级尺寸门槛 (width >= 400 && height >= 260)，且处于标准层 (0...15)；
            // 3. 特征 C（全屏物理视窗）：处于全屏 Space 的有效业务窗口，无论有无标题，均属标准窗口候选。
            if AutoQuitQuirks.isNativeFullscreenSize(width: width, height: height) {
                return true
            }
            return (!rawName.isEmpty && width > 120 && height > 70) || (width >= 400 && height >= 260)
        }
    }

    /// WindowServer 层面标准应用窗口计数（Layer 0...15，纯几何公开信息，结合 AutoQuitQuirks 规则清洗离屏幽灵）
    public static func windowServerStandardWindowCount(for pid: pid_t, bundleID: String? = nil) -> Int? {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let resolvedBundleID = bundleID ?? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier

        var count = 0
        for w in list {
            guard let ownerPID = w[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else { continue }
            guard let layer = w[kCGWindowLayer as String] as? Int, (0...15).contains(layer) else { continue }
            guard let alpha = w[kCGWindowAlpha as String] as? Double, alpha > 0.01 else { continue }
            guard let bounds = w[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double,
                  width > 40, height > 40 else { continue }

            let ownerName = (w[kCGWindowOwnerName as String] as? String) ?? ""
            let rawName = (w[kCGWindowName as String] as? String) ?? ""
            let isOnScreen = (w[kCGWindowIsOnscreen as String] as? Bool) ?? false

            if isStandardWindowCandidate(
                bundleID: resolvedBundleID,
                ownerName: ownerName,
                rawName: rawName,
                width: width,
                height: height,
                isOnScreen: isOnScreen
            ) {
                count += 1
            }
        }
        return count
    }

    /// WindowServer 层面在屏标准窗口数（Layer 0...15，仅统计 isOnScreen == true 的有效在屏业务窗口）
    public static func windowServerOnScreenWindowCount(for pid: pid_t, bundleID: String? = nil) -> Int? {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let resolvedBundleID = bundleID ?? NSRunningApplication(processIdentifier: pid)?.bundleIdentifier

        var count = 0
        for w in list {
            guard let ownerPID = w[kCGWindowOwnerPID as String] as? pid_t, ownerPID == pid else { continue }
            guard let layer = w[kCGWindowLayer as String] as? Int, (0...15).contains(layer) else { continue }
            guard let alpha = w[kCGWindowAlpha as String] as? Double, alpha > 0.01 else { continue }
            guard let bounds = w[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? Double,
                  let height = bounds["Height"] as? Double,
                  width > 40, height > 40 else { continue }

            let ownerName = (w[kCGWindowOwnerName as String] as? String) ?? ""
            let rawName = (w[kCGWindowName as String] as? String) ?? ""
            let isOnScreen = (w[kCGWindowIsOnscreen as String] as? Bool) ?? false

            if isOnScreen && isStandardWindowCandidate(
                bundleID: resolvedBundleID,
                ownerName: ownerName,
                rawName: rawName,
                width: width,
                height: height,
                isOnScreen: true
            ) {
                count += 1
            }
        }
        return count
    }

    /// 实例级别零窗确认：结合当前进程的 AX 查询与 WindowServer 计数
    public static func isConfirmedZeroWindows(pid: pid_t, axCount: Int?, bundleID: String? = nil) -> Bool {
        let wsCount = windowServerStandardWindowCount(for: pid, bundleID: bundleID)
        return isConfirmedZeroWindowCount(axCount: axCount, windowServerCount: wsCount)
    }

    /// 通过 libproc proc_listpids + proc_pidpath 极速在内核中根据可执行文件路径或 Bundle 路径反查真实 PID（含 NFC 规范化）
    public static func resolveProcessIdentifier(for app: NSRunningApplication) -> pid_t? {
        let pid = app.processIdentifier
        if pid > 0 { return pid }

        if let rawTargetPath = app.executableURL?.path ?? app.bundleURL?.path {
            let targetPath = rawTargetPath.precomposedStringWithCanonicalMapping
            let targetPrefix = targetPath.hasSuffix("/") ? targetPath : (targetPath + "/")
            var pids = [pid_t](repeating: 0, count: 2048)
            let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(MemoryLayout<pid_t>.size * pids.count))
            let count = Int(bytes) / MemoryLayout<pid_t>.size
            var pathBuffer = [CChar](repeating: 0, count: 4096)
            for i in 0..<count {
                let p = pids[i]
                guard p > 0, p != ProcessInfo.processInfo.processIdentifier else { continue }
                let len = proc_pidpath(p, &pathBuffer, UInt32(pathBuffer.count))
                if len > 0 {
                    let path = String(cString: pathBuffer).precomposedStringWithCanonicalMapping
                    if path == targetPath || path.hasPrefix(targetPrefix) {
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

    // MARK: - 内部状态机（Y-02：锁内仅做内存状态读写，AX / WindowServer IPC 移至锁外执行）

    private func start() {
        assert(Thread.isMainThread)
        os_unfair_lock_lock(&lock)
        if isRunning {
            os_unfair_lock_unlock(&lock)
            return
        }
        isRunning = true
        os_unfair_lock_unlock(&lock)

        for app in NSWorkspace.shared.runningApplications {
            attachIfEligible(app)
        }

        let timer = Timer(timeInterval: 1.0, target: self, selector: #selector(fallbackPoll), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        os_unfair_lock_lock(&lock)
        fallbackTimer = timer
        let watchedCount = watched.count
        os_unfair_lock_unlock(&lock)
        runtimeLog("[AutoQuit] Started; watching \(watchedCount) regular app(s).")
    }

    public func stop() {
        assert(Thread.isMainThread)
        os_unfair_lock_lock(&lock)
        guard isRunning || !watched.isEmpty else {
            os_unfair_lock_unlock(&lock)
            return
        }
        let quitsToCancel = Array(pendingQuits.values)
        pendingQuits.removeAll()
        let rechecksToCancel = Array(pendingRechecks.values)
        pendingRechecks.removeAll()
        terminatingPids.removeAll()
        recheckCounts.removeAll()
        suppressedPids.removeAll()
        let entriesToTeardown = Array(watched.values)
        watched.removeAll()
        let timerToInvalidate = fallbackTimer
        fallbackTimer = nil
        isRunning = false
        os_unfair_lock_unlock(&lock)

        for work in quitsToCancel { work.cancel() }
        for work in rechecksToCancel { work.cancel() }
        for entry in entriesToTeardown {
            teardownObserver(entry.observer, axApp: entry.axApp, windowRefs: entry.registeredWindowRefs)
        }
        timerToInvalidate?.invalidate()
        AutoQuitUndoHUDController.shared.dismiss()
        runtimeLog("[AutoQuit] Stopped; all AX observers released.")
    }

    private func attachIfEligible(_ app: NSRunningApplication) {
        // 运行时自愈：在进程附着前，确保该运行应用已登记于 AppHotspotIndex
        AppHotspotIndex.shared.registerRunningAppIfNeeded(app)

        guard let pid = AutoQuitManager.resolveProcessIdentifier(for: app), pid > 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.attachIfEligible(app)
            }
            return
        }
        guard shouldAttach(app) else { return }

        os_unfair_lock_lock(&lock)
        let alreadyWatched = (watched[pid] != nil)
        let running = isRunning
        os_unfair_lock_unlock(&lock)
        guard running, !alreadyWatched else { return }

        var observer: AXObserver?
        let createErr = AXObserverCreate(pid, autoQuitObserverCallback, &observer)
        guard createErr == .success, let obs = observer else {
            runtimeLog("[AutoQuit] AXObserverCreate failed for pid \(pid): error \(createErr.rawValue)")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .commonModes)

        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 0.15)

        // Y-03: 检查并记录 AXObserverAddNotification 错误码
        let errCreated = AXObserverAddNotification(obs, axApp, kAXWindowCreatedNotification as CFString, nil)
        let errClosed = AXObserverAddNotification(obs, axApp, kAXWindowClosedNotification, nil)
        let errDestroyed = AXObserverAddNotification(obs, axApp, kAXUIElementDestroyedNotification as CFString, nil)
        let isAXObserverDegraded = (errCreated != .success && errClosed != .success && errDestroyed != .success)
        if isAXObserverDegraded {
            runtimeLog("[AutoQuit] AXObserverAddNotification warnings for pid \(pid): created=\(errCreated.rawValue), closed=\(errClosed.rawValue), destroyed=\(errDestroyed.rawValue)")
        }

        // Y-02: 在锁外执行 AX 与 WindowServer 初始窗口探测
        let existing = axWindows(of: axApp)
        let wsCount = AutoQuitManager.windowServerStandardWindowCount(for: pid, bundleID: app.bundleIdentifier)
        var registeredRefs: [AXUIElement] = []
        var hadWindows = false

        if let list = existing, !list.isEmpty {
            hadWindows = true
            for window in list {
                if AXObserverAddNotification(obs, window, kAXUIElementDestroyedNotification as CFString, nil) == .success {
                    registeredRefs.append(window)
                }
            }
        } else if let ws = wsCount, ws > 0 {
            hadWindows = true
        }

        let newEntry = WatchedApp(
            app: app,
            axApp: axApp,
            observer: obs,
            registeredWindowRefs: registeredRefs,
            hadWindows: hadWindows,
            lastActiveDate: app.isActive ? Date() : .distantPast,
            lastCloseEventDate: .distantPast,
            isAXObserverDegraded: isAXObserverDegraded
        )

        os_unfair_lock_lock(&lock)
        if isRunning && watched[pid] == nil {
            watched[pid] = newEntry
            os_unfair_lock_unlock(&lock)
            let knownCount = existing.map { String($0.count) } ?? (wsCount.map { "ws:\($0)" } ?? "unknown")
            runtimeLog("[AutoQuit] Watching \(app.localizedName ?? "pid \(pid)") (windows: \(knownCount))")
        } else {
            os_unfair_lock_unlock(&lock)
            teardownObserver(obs, axApp: axApp, windowRefs: registeredRefs)
        }
    }

    private func handleAppActivated(_ app: NSRunningApplication) {
        guard let pid = AutoQuitManager.resolveProcessIdentifier(for: app), pid > 0 else {
            attachIfEligible(app)
            return
        }
        os_unfair_lock_lock(&lock)
        let existingEntry = watched[pid]
        os_unfair_lock_unlock(&lock)

        guard let entrySnapshot = existingEntry else {
            attachIfEligible(app)
            return
        }

        // Y-02: 锁外探测 AX 与 WindowServer
        let list = axWindows(of: entrySnapshot.axApp)
        let axCount = list?.count
        let wsCount = AutoQuitManager.windowServerStandardWindowCount(for: pid, bundleID: app.bundleIdentifier)

        os_unfair_lock_lock(&lock)
        guard var entry = watched[pid] else {
            os_unfair_lock_unlock(&lock)
            return
        }
        entry.lastActiveDate = Date()
        if (axCount ?? 0) > 0 || (wsCount ?? 0) > 0 {
            entry.hadWindows = true
            // Y-04: 应用重新激活并拥有窗口时，自动解除本轮会话的取消抑制状态
            suppressedPids.remove(pid)
            cancelPendingQuitLocked(pid)
            if let list = list {
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
        os_unfair_lock_unlock(&lock)
    }

    private func handleAppDeactivated(_ app: NSRunningApplication) {
        guard let pid = AutoQuitManager.resolveProcessIdentifier(for: app), pid > 0 else { return }
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        if var entry = watched[pid] {
            entry.lastActiveDate = Date()
            watched[pid] = entry
            let recentlyHadCloseEvent = Date().timeIntervalSince(entry.lastCloseEventDate) < 3.0
            if !recentlyHadCloseEvent {
                cancelPendingQuitLocked(pid)
                cancelPendingRecheckLocked(pid)
            }
        }
    }

    private func detach(pid: pid_t) {
        os_unfair_lock_lock(&lock)
        cancelPendingQuitLocked(pid)
        terminatingPids.remove(pid)
        recheckCounts.removeValue(forKey: pid)
        // Y-04: 进程终止时清理抑制记录，防止系统复用 PID 后继承旧进程的抑制态
        suppressedPids.remove(pid)
        let removedEntry = watched.removeValue(forKey: pid)
        os_unfair_lock_unlock(&lock)

        if let entry = removedEntry {
            teardownObserver(entry.observer, axApp: entry.axApp, windowRefs: entry.registeredWindowRefs)
        }
    }

    func handleAXNotification(pid: pid_t, element: AXUIElement, notificationName: String) {
        assert(Thread.isMainThread)
        os_unfair_lock_lock(&lock)
        guard isRunning, var entry = watched[pid] else {
            os_unfair_lock_unlock(&lock)
            return
        }

        if notificationName == kAXWindowCreatedNotification as String {
            terminatingPids.remove(pid)
            recheckCounts.removeValue(forKey: pid)
            // Y-04: 应用新建窗口时清除取消抑制状态，使其后续关窗可正常触发自动退出
            suppressedPids.remove(pid)
            cancelPendingRecheckLocked(pid)
            if !entry.registeredWindowRefs.contains(where: { CFEqual($0, element) }) {
                if AXObserverAddNotification(entry.observer, element, kAXUIElementDestroyedNotification as CFString, nil) == .success {
                    entry.registeredWindowRefs.append(windowElement(from: element))
                }
            }
            watched[pid] = entry
            let axApp = entry.axApp
            let bundleId = entry.app.bundleIdentifier
            os_unfair_lock_unlock(&lock)

            // Y-02: 锁外执行 AX 与 WindowServer 查询
            let axCount = axWindows(of: axApp)?.count
            let wsCount = AutoQuitManager.windowServerStandardWindowCount(for: pid, bundleID: bundleId)
            let isBusiness = Self.isStandardBusinessWindow(element)

            if (axCount ?? 0) > 0 || (wsCount ?? 0) > 0 || isBusiness {
                os_unfair_lock_lock(&lock)
                if var latestEntry = watched[pid] {
                    latestEntry.hadWindows = true
                    watched[pid] = latestEntry
                    cancelPendingQuitLocked(pid)
                }
                os_unfair_lock_unlock(&lock)
            }
        } else if notificationName == (kAXWindowClosedNotification as String)
                    || notificationName == (kAXUIElementDestroyedNotification as String) {
            let isKnownWindow = entry.registeredWindowRefs.contains(where: { CFEqual($0, element) })
            let isActive = entry.app.isActive
            let hasRegisteredWindows = !entry.registeredWindowRefs.isEmpty

            // 军师审定防线：
            // 1. 若为非已知窗口且应用已处于后台，直接丢弃，严禁失焦销毁浮层（Tooltip/下拉菜单）伪造关窗
            if !isKnownWindow && !isActive {
                os_unfair_lock_unlock(&lock)
                return
            }

            // 2. 若为非已知窗口且已有已注册的业务窗口，当前通知必定为临时浮层，直接丢弃
            if !isKnownWindow && hasRegisteredWindows {
                os_unfair_lock_unlock(&lock)
                return
            }

            // 3. 若为非已知窗口且 registeredWindowRefs 为空（可能启动期未抓到引用）：
            //    必须在锁外做 isStandardBusinessWindow 业务窗口核验，排除纯提示浮层
            if !isKnownWindow {
                os_unfair_lock_unlock(&lock)
                let isBusiness = Self.isStandardBusinessWindow(element)
                guard isBusiness else { return }
                os_unfair_lock_lock(&lock)
                guard isRunning, let currentEntry = watched[pid] else {
                    os_unfair_lock_unlock(&lock)
                    return
                }
                entry = currentEntry
            }

            entry.registeredWindowRefs.removeAll(where: { CFEqual($0, element) })
            entry.lastCloseEventDate = Date()
            if !entry.hadWindows {
                if notificationName == (kAXWindowClosedNotification as String) || isKnownWindow {
                    entry.hadWindows = true
                }
            }
            let hadWin = entry.hadWindows
            watched[pid] = entry
            os_unfair_lock_unlock(&lock)

            guard hadWin else { return }
            evaluateAppWindows(pid: pid)
        } else {
            os_unfair_lock_unlock(&lock)
        }
    }

    @inline(__always)
    private func windowElement(from element: AXUIElement) -> AXUIElement {
        return element
    }

    private func evaluateAppWindows(pid: pid_t) {
        assert(Thread.isMainThread)
        os_unfair_lock_lock(&lock)
        guard isRunning, let entrySnapshot = watched[pid] else {
            os_unfair_lock_unlock(&lock)
            return
        }
        let spaceChangedRecently = Date().timeIntervalSince(lastSpaceChangeDate) < 2.0
        if spaceChangedRecently {
            cancelPendingQuitLocked(pid)
            cancelPendingRecheckLocked(pid)
            os_unfair_lock_unlock(&lock)
            return
        }
        let app = entrySnapshot.app
        guard !app.isTerminated else {
            os_unfair_lock_unlock(&lock)
            return
        }
        let recentlyHadCloseEvent = Date().timeIntervalSince(entrySnapshot.lastCloseEventDate) < 3.0
        if !app.isActive && Date().timeIntervalSince(entrySnapshot.lastActiveDate) < 2.0 && !recentlyHadCloseEvent {
            cancelPendingQuitLocked(pid)
            cancelPendingRecheckLocked(pid)
            os_unfair_lock_unlock(&lock)
            return
        }
        os_unfair_lock_unlock(&lock)

        // Y-02: 锁外执行 AX 与 WindowServer 查询
        let axCount = axWindows(of: entrySnapshot.axApp)?.count
        if app.isHidden {
            let hadCloseEvent = entrySnapshot.lastCloseEventDate != .distantPast
            if !hadCloseEvent || (axCount ?? 1) > 0 {
                return
            }
        }

        if let ax = axCount, ax > 0 {
            os_unfair_lock_lock(&lock)
            if var latest = watched[pid], !latest.hadWindows {
                latest.hadWindows = true
                watched[pid] = latest
            }
            recheckCounts.removeValue(forKey: pid)
            cancelPendingQuitLocked(pid)
            os_unfair_lock_unlock(&lock)
            return
        }

        os_unfair_lock_lock(&lock)
        guard isRunning, let currentEntry = watched[pid], currentEntry.hadWindows else {
            os_unfair_lock_unlock(&lock)
            return
        }
        os_unfair_lock_unlock(&lock)

        let wsCount = AutoQuitManager.windowServerStandardWindowCount(for: pid, bundleID: app.bundleIdentifier)
        let wsOnscreen = AutoQuitManager.windowServerOnScreenWindowCount(for: pid, bundleID: app.bundleIdentifier)
        let isZeroByCausality = (axCount == 0) && ((wsCount ?? 0) == 0) && ((wsOnscreen ?? 0) == 0) && recentlyHadCloseEvent

        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard isRunning, watched[pid] != nil else { return }

        // Y-01 & 军师第三层因果律防线：
        // 1. 标准双零确认 (axCount == 0 && wsCount == 0)；
        // 2. 真实关窗因果律确认：axCount == 0 且在屏窗口 wsOnscreen == 0 且刚刚发生真实关窗 (recentlyHadCloseEvent)。
        //    说明当前屏幕上已没有任何可见窗口，残存的 wsCount 均为 orderOut: 离屏残余底板，放行调度！
        if isZeroByCausality || AutoQuitManager.isConfirmedZeroWindowCount(axCount: axCount, windowServerCount: wsCount) {
            recheckCounts.removeValue(forKey: pid)
            cancelPendingRecheckLocked(pid)
            scheduleQuitLocked(pid, app: app)
        } else if axCount == 0 && ((wsCount ?? 0) > 0 || wsCount == nil) {
            guard pendingRechecks[pid] == nil else { return }

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
                recheckCounts.removeValue(forKey: pid)
                cancelPendingQuitLocked(pid)
                AutoQuitDecisionTrace.shared.record(
                    pid: pid,
                    bundleID: app.bundleIdentifier ?? "",
                    appName: app.localizedName ?? "",
                    axWindowCount: axCount,
                    wsWindowCount: wsCount,
                    decision: .aborted,
                    reasonCode: wsCount == nil ? "WindowServerQueryUnknown" : "WindowServerConfirmedOnscreen",
                    detail: wsCount == nil ? "WindowServer 状态未知，安全放弃退出" : "防抖期后 WindowServer 仍有在屏实体窗口"
                )
            }
        } else if (axCount ?? 0) > 0 || (wsCount ?? 0) > 0 {
            recheckCounts.removeValue(forKey: pid)
            cancelPendingQuitLocked(pid)
        }
    }

    /// Y-02: 兜底轮询先在锁内提取轻量快照，再在后台 probeQueue 执行 AX / WindowServer IPC 查询，绝不阻塞主线程
    @objc private func fallbackPoll() {
        assert(Thread.isMainThread)
        guard isRunning else { return }

        for app in NSWorkspace.shared.runningApplications {
            if let pid = AutoQuitManager.resolveProcessIdentifier(for: app), pid > 0 {
                os_unfair_lock_lock(&lock)
                let isWatched = (watched[pid] != nil)
                os_unfair_lock_unlock(&lock)
                if !isWatched && shouldAttach(app) {
                    attachIfEligible(app)
                }
            }
        }

        let now = Date()
        os_unfair_lock_lock(&lock)
        if isFallbackProbeInFlight {
            os_unfair_lock_unlock(&lock)
            return
        }
        var unhaddedToProbe: [(pid: pid_t, axApp: AXUIElement, bundleId: String?)] = []
        var activeToEvaluate: [pid_t] = []

        for (pid, entry) in watched {
            guard pendingQuits[pid] == nil,
                  pendingRechecks[pid] == nil,
                  !terminatingPids.contains(pid) else { continue }
            if !entry.hadWindows {
                unhaddedToProbe.append((pid: pid, axApp: entry.axApp, bundleId: entry.app.bundleIdentifier))
            } else {
                let isActive = entry.app.isActive
                let recentlyHadCloseEvent = now.timeIntervalSince(entry.lastCloseEventDate) < 3.0
                if isActive || recentlyHadCloseEvent || entry.isAXObserverDegraded {
                    activeToEvaluate.append(pid)
                }
            }
        }
        if !unhaddedToProbe.isEmpty {
            isFallbackProbeInFlight = true
        }
        os_unfair_lock_unlock(&lock)

        for pid in activeToEvaluate {
            evaluateAppWindows(pid: pid)
        }

        guard !unhaddedToProbe.isEmpty else { return }

        probeQueue.async { [weak self] in
            guard let self = self else { return }
            var discoveredWindows: [(pid: pid_t, windows: [AXUIElement])] = []
            for item in unhaddedToProbe {
                let list = self.axWindows(of: item.axApp)
                let axCount = list?.count ?? 0
                let wsCount = AutoQuitManager.windowServerStandardWindowCount(for: item.pid, bundleID: item.bundleId) ?? 0
                if axCount > 0 || wsCount > 0 {
                    discoveredWindows.append((pid: item.pid, windows: list ?? []))
                }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                os_unfair_lock_lock(&self.lock)
                self.isFallbackProbeInFlight = false
                guard self.isRunning else {
                    os_unfair_lock_unlock(&self.lock)
                    return
                }
                for found in discoveredWindows {
                    if var entry = self.watched[found.pid] {
                        entry.hadWindows = true
                        for window in found.windows {
                            if !entry.registeredWindowRefs.contains(where: { CFEqual($0, window) }) {
                                if AXObserverAddNotification(entry.observer, window, kAXUIElementDestroyedNotification as CFString, nil) == .success {
                                    entry.registeredWindowRefs.append(window)
                                }
                            }
                        }
                        self.watched[found.pid] = entry
                    }
                }
                os_unfair_lock_unlock(&self.lock)
            }
        }
    }

    private func scheduleQuitLocked(_ pid: pid_t, app: NSRunningApplication) {
        guard watched[pid] != nil else { return }
        guard pendingQuits[pid] == nil else { return }
        guard !terminatingPids.contains(pid) else { return }

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

        if var entry = watched[pid] {
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
            if ConfigManager.shared.config.enableAutoQuitUndoHUD {
                // Y-04: 显式传入已解析的真实 pid，防止 app.processIdentifier == -1 导致取消失效
                AutoQuitUndoHUDController.shared.showCountdown(for: app, resolvedPid: pid, seconds: delaySeconds) { [weak self] cancelledPid in
                    guard let self = self else { return }
                    let targetPid = (cancelledPid > 0) ? cancelledPid : pid
                    os_unfair_lock_lock(&self.lock)
                    self.cancelPendingQuitLocked(targetPid)
                    self.suppressedPids.insert(targetPid)
                    os_unfair_lock_unlock(&self.lock)
                    AutoQuitDecisionTrace.shared.record(
                        pid: targetPid,
                        bundleID: app.bundleIdentifier ?? "",
                        appName: app.localizedName ?? "pid \(targetPid)",
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

    private func executePendingQuit(pid: pid_t) {
        assert(Thread.isMainThread)
        AutoQuitUndoHUDController.shared.dismiss(forPid: pid)

        os_unfair_lock_lock(&lock)
        pendingQuits[pid] = nil
        guard isRunning, let entrySnapshot = watched[pid] else {
            os_unfair_lock_unlock(&lock)
            return
        }
        let spaceChangedRecently = Date().timeIntervalSince(lastSpaceChangeDate) < 2.0
        if spaceChangedRecently {
            os_unfair_lock_unlock(&lock)
            return
        }
        let app = entrySnapshot.app
        guard !app.isTerminated else {
            os_unfair_lock_unlock(&lock)
            return
        }
        let recentlyHadCloseEvent = Date().timeIntervalSince(entrySnapshot.lastCloseEventDate) < 5.0
        if !app.isActive && Date().timeIntervalSince(entrySnapshot.lastActiveDate) < 2.0 && !recentlyHadCloseEvent {
            os_unfair_lock_unlock(&lock)
            return
        }
        os_unfair_lock_unlock(&lock)

        let cfg = ConfigManager.shared.config
        guard cfg.enableAutoQuit else { return }
        let resolvedPid = AutoQuitManager.resolveProcessIdentifier(for: app) ?? pid
        guard AutoQuitManager.shouldWatch(
            bundleID: app.bundleIdentifier,
            activationPolicy: app.activationPolicy,
            isFinishedLaunching: app.isFinishedLaunching,
            isSelf: resolvedPid == ProcessInfo.processInfo.processIdentifier,
            mode: cfg.autoQuitMode,
            rules: cfg.autoQuitAppRules
        ) else { return }

        // Y-02: 锁外执行终审 AX 与 WindowServer 计数
        let axCount = axWindows(of: entrySnapshot.axApp)?.count
        let wsCount = AutoQuitManager.windowServerStandardWindowCount(for: pid, bundleID: app.bundleIdentifier)
        let wsOnscreen = AutoQuitManager.windowServerOnScreenWindowCount(for: pid, bundleID: app.bundleIdentifier)
        let isZeroByCausality = (axCount == 0) && ((wsCount ?? 0) == 0) && ((wsOnscreen ?? 0) == 0) && recentlyHadCloseEvent

        if app.isHidden {
            let hadCloseEvent = entrySnapshot.lastCloseEventDate != .distantPast
            if !hadCloseEvent || (axCount ?? 1) > 0 {
                return
            }
        }

        if app.isActive && !isZeroByCausality && ((axCount ?? 0) > 0 || (wsCount ?? 0) > 0) {
            runtimeLog("[AutoQuit] Aborted quit for \(app.localizedName ?? "pid \(pid)"): app is active and has window (AX=\(axCount.map(String.init) ?? "nil"), WS=\(wsCount.map(String.init) ?? "nil")).")
            AutoQuitDecisionTrace.shared.record(
                pid: pid,
                bundleID: app.bundleIdentifier ?? "",
                appName: app.localizedName ?? "",
                axWindowCount: axCount,
                wsWindowCount: wsCount,
                decision: .aborted,
                reasonCode: "ActiveWithWindowsOnFinalCheck"
            )
            return
        }

        guard isZeroByCausality || AutoQuitManager.isConfirmedZeroWindowCount(axCount: axCount, windowServerCount: wsCount) else {
            runtimeLog("[AutoQuit] Aborted quit for \(app.localizedName ?? "pid \(pid)"): windows still present or unknown (AX=\(axCount.map(String.init) ?? "nil"), WS=\(wsCount.map(String.init) ?? "nil")).")
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

        os_unfair_lock_lock(&lock)
        guard isRunning, watched[pid] != nil, !suppressedPids.contains(pid) else {
            os_unfair_lock_unlock(&lock)
            return
        }
        terminatingPids.insert(pid)
        recheckCounts.removeValue(forKey: pid)
        cancelPendingRecheckLocked(pid)
        os_unfair_lock_unlock(&lock)

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
        terminateCompanionHelpers(for: app)
    }

    /// 伴生 Helper 联动退出（含军师加固点 3：APFS Unicode NFC 规范化前缀校验）
    private func terminateCompanionHelpers(for mainApp: NSRunningApplication) {
        guard let rawMainBundlePath = mainApp.bundleURL?.path else { return }
        let mainBundlePath = rawMainBundlePath.precomposedStringWithCanonicalMapping
        let mainBid = mainApp.bundleIdentifier ?? ""
        let mainOwner = mainApp.localizedName ?? ""
        let companions = Set(AutoQuitQuirks.shared.companionBundleIDs(for: mainBid, ownerName: mainOwner))
        let terminateInBundle = AutoQuitQuirks.shared.shouldTerminateHelpersInBundle(for: mainBid, ownerName: mainOwner)

        guard !companions.isEmpty || terminateInBundle else { return }

        for running in NSWorkspace.shared.runningApplications {
            guard running.processIdentifier != mainApp.processIdentifier, !running.isTerminated else { continue }
            guard let rawHelperPath = running.bundleURL?.path else { continue }
            let helperPath = rawHelperPath.precomposedStringWithCanonicalMapping
            let helperBid = running.bundleIdentifier ?? ""

            let isExplicitCompanion = !helperBid.isEmpty && companions.contains(helperBid)
            let isPhysicallyInsideBundle = helperPath.hasPrefix(mainBundlePath + "/Contents/")

            if (isExplicitCompanion || terminateInBundle) && isPhysicallyInsideBundle {
                runtimeLog("[AutoQuit] Terminating companion helper \(running.localizedName ?? helperBid) (pid: \(running.processIdentifier)) inside \(mainApp.localizedName ?? mainBid)")
                running.terminate()
            }
        }
    }

    private func cancelPendingRecheckLocked(_ pid: pid_t) {
        if let work = pendingRechecks.removeValue(forKey: pid) {
            work.cancel()
        }
    }

    private func cancelAllPendingTasks() {
        os_unfair_lock_lock(&lock)
        let quits = Array(pendingQuits.values)
        pendingQuits.removeAll()
        let rechecks = Array(pendingRechecks.values)
        pendingRechecks.removeAll()
        recheckCounts.removeAll()
        os_unfair_lock_unlock(&lock)

        for work in quits { work.cancel() }
        for work in rechecks { work.cancel() }
        AutoQuitUndoHUDController.shared.dismiss()
    }

    private func cancelPendingQuitLocked(_ pid: pid_t) {
        recheckCounts.removeValue(forKey: pid)
        cancelPendingRecheckLocked(pid)
        if let work = pendingQuits.removeValue(forKey: pid) {
            work.cancel()
            DispatchQueue.main.async {
                AutoQuitUndoHUDController.shared.dismiss(forPid: pid)
            }
        }
    }

    private func teardownObserver(_ observer: AXObserver, axApp: AXUIElement? = nil, windowRefs: [AXUIElement] = []) {
        if let axApp = axApp {
            _ = AXObserverRemoveNotification(observer, axApp, kAXWindowCreatedNotification as CFString)
            _ = AXObserverRemoveNotification(observer, axApp, kAXWindowClosedNotification)
            _ = AXObserverRemoveNotification(observer, axApp, kAXUIElementDestroyedNotification as CFString)
        }
        for win in windowRefs {
            _ = AXObserverRemoveNotification(observer, win, kAXUIElementDestroyedNotification as CFString)
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    /// 返回 nil 表示 AX 查询失败（状态未知），调用方必须跳过本轮判定；
    /// Y-03：彻底废除 as! 强制向下转换，使用 CFGetTypeID 与条件转换保障绝对类型安全。
    private func axWindows(of element: AXUIElement) -> [AXUIElement]? {
        AXUIElementSetMessagingTimeout(element, 0.15)
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value)
        var result: [AXUIElement] = (err == .success ? (value as? [AXUIElement] ?? []) : [])

        if result.isEmpty {
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            let wsCount = (pid > 0) ? AutoQuitManager.windowServerStandardWindowCount(for: pid) : nil
            if (wsCount ?? 0) > 0 {
                for attr in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
                    var winVal: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, attr as CFString, &winVal) == .success,
                       let win = winVal,
                       CFGetTypeID(win) == AXUIElementGetTypeID() {
                        let winEl = unsafeBitCast(win, to: AXUIElement.self)
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

        if err == .noValue && result.isEmpty {
            var appRole: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &appRole) == .success {
                return []
            }
        }

        if err != .success && result.isEmpty {
            return nil
        }
        return result.filter { Self.isStandardBusinessWindow($0) }
    }

    /// Y-01 & Y-03：判断是否为有效业务窗口或对话框
    /// 1. 消除 `s as! AXValue` 强转，改用 `CFGetTypeID(s) == AXValueGetTypeID()` 安全解包；
    /// 2. 具备关闭/最小化按钮或属于系统对话框/模态窗的窗口优先核验；
    /// 3. 军师加固门禁：若既无关闭又无最小化按钮，且物理尺寸 < 160x90（如夸克 40x40 桌面吸附小挂件），
    ///    判定为辅助悬浮挂件，严禁计入标准业务窗口！
    public static func isStandardBusinessWindow(_ w: AXUIElement) -> Bool {
        var sizeVal: CFTypeRef?
        var size: CGSize = .zero
        if AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &sizeVal) == .success,
           let s = sizeVal,
           CFGetTypeID(s) == AXValueGetTypeID() {
            let axVal = unsafeBitCast(s, to: AXValue.self)
            if AXValueGetType(axVal) == .cgSize {
                _ = AXValueGetValue(axVal, .cgSize, &size)
            }
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
            // 军师门禁：真实系统对话框/模态面板必有正常视窗尺寸 (>= 160x90)；
            // 若既无关闭按钮又无最小化按钮，且物理尺寸 < 160x90（如夸克 40x40 桌面小浮球/取词微元），
            // 判定为辅助悬浮挂件，严禁计入标准业务窗口！
            if !hasClose && !hasMin && size != .zero && (size.width < 160 || size.height < 90) {
                return false
            }
            return true
        }

        var modalVal: CFTypeRef?
        if AXUIElementCopyAttributeValue(w, "AXModal" as CFString, &modalVal) == .success, (modalVal as? Bool) == true {
            return true
        }

        if size != .zero && (size.width < 160 || size.height < 90) {
            return false
        }

        if size.width > 320 && size.height > 200 {
            return true
        }

        return false
    }

    // MARK: - 诊断快照

    public func currentWatchedAppsSnapshot() -> [(name: String, bundleID: String, pid: pid_t, axCount: String, wsCount: String, rule: String)] {
        assert(Thread.isMainThread)
        os_unfair_lock_lock(&lock)
        let entriesSnapshot = Array(watched)
        os_unfair_lock_unlock(&lock)

        var result: [(name: String, bundleID: String, pid: pid_t, axCount: String, wsCount: String, rule: String)] = []
        for (pid, entry) in entriesSnapshot {
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
