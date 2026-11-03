import Foundation
import AppKit
import Darwin
import CoreServices

public struct IndexedApp: Sendable {
    public let name: String
    public let localizedName: String
    public let path: String
    public let bundleId: String?
    public let aliases: [String]
    /// Lowercased once at index time; `search` runs on every keystroke on the main thread.
    public let lowercasedAliases: [String]
    public let pinyins: [String]
    public let pinyinAbbrs: [String]
    public let isRegularApp: Bool
    public let isShelfEligible: Bool

    public init(name: String, localizedName: String, path: String, bundleId: String?, isRegularApp: Bool = true, isShelfEligible: Bool = true, additionalAliases: [String] = []) {
        self.name = name
        self.localizedName = localizedName
        self.path = path
        self.bundleId = bundleId
        self.isRegularApp = isRegularApp
        self.isShelfEligible = isShelfEligible

        var allAliases = Set<String>()
        allAliases.insert(name)
        allAliases.insert(localizedName)
        for a in additionalAliases where !a.isEmpty {
            allAliases.insert(a)
        }
        // Q-12: 固定排序保证拼音与别名顺序确定性，消除 Set 随机哈希顺序导致的搜索得分抖动
        self.aliases = Array(allAliases).sorted()
        self.lowercasedAliases = self.aliases.map { $0.lowercased() }

        var pinyinList: [String] = []
        var abbrList: [String] = []

        for alias in self.aliases {
            let (full, abbr) = IndexedApp.pinyinAndAbbr(alias)
            if !full.isEmpty {
                pinyinList.append(full)
            }
            if !abbr.isEmpty {
                abbrList.append(abbr)
            }
        }

        self.pinyins = pinyinList
        self.pinyinAbbrs = abbrList
    }

    private static func pinyinAndAbbr(_ text: String) -> (full: String, abbr: String) {
        let mutableString = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutableString, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
        let spaced = mutableString as String
        let words = spaced.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        var abbr = ""
        for w in words where !w.isEmpty {
            if let first = w.first {
                abbr.append(first)
            }
        }
        let full = spaced.replacingOccurrences(of: " ", with: "")
        return (full.lowercased(), abbr.lowercased())
    }
}

public final class AppHotspotIndex {
    public static let shared = AppHotspotIndex()

    private var apps: [IndexedApp] = []
    private let appsLock = NSLock()
    private let queue = DispatchQueue(label: "cc.atools.appindex", qos: .utility)
    private var lastRefreshDate = Date.distantPast
    private var isScanInProgress = false
    private var directorySources: [DispatchSourceFileSystemObject] = []
    private var debounceWorkItem: DispatchWorkItem?

    // MARK: - FSEventStream 递归深度监控与就绪态轮询
    private var eventStream: FSEventStreamRef?
    private var workspaceLaunchObserver: NSObjectProtocol?

    private struct InFlightAppEntry {
        let path: String
        var lastSize: Int64
        var unchangedCount: Int
        let firstDetectedAt: Date
    }
    private var inFlightApps: [String: InFlightAppEntry] = [:]
    private var inFlightCheckWorkItem: DispatchWorkItem?

    private init() {
        refreshIndex()
        startWatchingAppDirectories()
        startFSEventsWatcher()
        startWorkspaceMonitoring()
    }

    deinit {
        for source in directorySources {
            source.cancel()
        }
        stopFSEventsWatcher()
        if let obs = workspaceLaunchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        inFlightCheckWorkItem?.cancel()
    }

    private func startWatchingAppDirectories() {
        let home = NSHomeDirectory()
        let watchDirs = ["/Applications", "\(home)/Applications"]
        for dir in watchDirs {
            guard FileManager.default.fileExists(atPath: dir) else { continue }
            let fd = open(dir, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .link, .rename, .extend, .attrib],
                queue: queue
            )
            source.setEventHandler { [weak self] in
                self?.scheduleDebouncedRefresh()
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            directorySources.append(source)
        }
    }

    // MARK: - FSEventStream 递归深度目录事件监控（方案 A：捕获 DMG/PKG/解压深层文件写入）
    private func startFSEventsWatcher() {
        let home = NSHomeDirectory()
        let watchPaths = ["/Applications", "\(home)/Applications"] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)

        let callback: FSEventStreamCallback = { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
            guard let clientCallBackInfo = clientCallBackInfo else { return }
            let index = Unmanaged<AppHotspotIndex>.fromOpaque(clientCallBackInfo).takeUnretainedValue()

            // 军师加固点 1：事件风暴抑制，仅当变更包含 .app 结构或核心元数据时响应防抖刷新
            if let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] {
                var hasRelevantAppChange = false
                for path in paths {
                    if path.contains(".app") {
                        hasRelevantAppChange = true
                        break
                    }
                }
                if hasRelevantAppChange {
                    index.scheduleDebouncedRefresh()
                }
            } else {
                index.scheduleDebouncedRefresh()
            }
        }

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            watchPaths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.5,
            flags
        ) else { return }

        self.eventStream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    private func stopFSEventsWatcher() {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
    }

    // MARK: - 运行时自愈监控（方案 C：应用首次启动即刻 O(1) 捕获并联动入库）
    private func startWorkspaceMonitoring() {
        let nc = NSWorkspace.shared.notificationCenter
        workspaceLaunchObserver = nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.registerRunningAppIfNeeded(app)
        }
    }

    /// 军师加固点 4：当常规应用启动时，若不在现有索引中，进行 O(1) 局部极速注入并同步
    public func registerRunningAppIfNeeded(_ app: NSRunningApplication) {
        // 严格限定为普通 GUI 窗口应用，杜绝后台守护或 Helper 进程误入抽屉和退出名单
        guard app.activationPolicy == .regular else { return }
        guard let bundleURL = app.bundleURL else { return }
        let path = bundleURL.path.precomposedStringWithCanonicalMapping
        let home = NSHomeDirectory()
        let isStandardAppDir = path.hasPrefix("/Applications") ||
                               path.hasPrefix("\(home)/Applications") ||
                               path.hasPrefix("/System/Applications") ||
                               path.hasPrefix("/System/Library/CoreServices/Applications")
        guard isStandardAppDir else { return }
        guard let bid = app.bundleIdentifier, !bid.isEmpty else { return }
        guard !AutoQuitManager.systemExcludedBundleIDs.contains(bid),
              bid != "cc.atools.app", bid != "cc.atools.app.dev" else { return }

        appsLock.lock()
        let isAlreadyKnown = apps.contains { $0.bundleId == bid || $0.path == path }
        appsLock.unlock()

        if isAlreadyKnown { return }

        queue.async { [weak self] in
            guard let self = self else { return }
            let baseName = (path as NSString).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            let resourceValues = try? bundleURL.resourceValues(forKeys: [.localizedNameKey])
            let lsName = resourceValues?.localizedName?.replacingOccurrences(of: ".app", with: "", options: .caseInsensitive)
            let metadata = AppMetadataReader.read(appURL: bundleURL)
            var aliases: [String] = []
            if let ls = lsName, !ls.isEmpty && ls != baseName { aliases.append(ls) }
            aliases.append(contentsOf: metadata.localizedNames)
            if let disp = metadata.displayName, !disp.isEmpty { aliases.append(disp) }
            if let bName = metadata.bundleName, !bName.isEmpty { aliases.append(bName) }

            let primaryLocalizedName = aliases.first ?? lsName ?? app.localizedName ?? baseName
            let isShelfEligible = !metadata.isBackgroundOnly && metadata.bundleIdentifier != nil && !(metadata.bundleIdentifier?.isEmpty ?? true)

            let indexed = IndexedApp(
                name: baseName,
                localizedName: primaryLocalizedName,
                path: path,
                bundleId: bid,
                isRegularApp: true,
                isShelfEligible: isShelfEligible,
                additionalAliases: aliases
            )

            self.appsLock.lock()
            if !self.apps.contains(where: { $0.bundleId == bid || $0.path == path }) {
                self.apps.append(indexed)
                let allApps = self.apps
                self.appsLock.unlock()
                runtimeLog("[AutoDiscovery] Self-healed runtime app: \(indexed.localizedName) (\(bid))")

                ConfigManager.shared.handleAppIndexUpdated(apps: allApps)

                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .atoolsAppIndexDidUpdate, object: nil)
                }
            } else {
                self.appsLock.unlock()
            }
        }
    }

    // MARK: - In-Flight 大型应用就绪态轮询追踪 (军师加固点 2)
    public func trackInFlightCandidate(path: String) {
        guard path.hasSuffix(".app") else { return }
        let home = NSHomeDirectory()
        guard path.hasPrefix("/Applications") || path.hasPrefix("\(home)/Applications") else { return }

        queue.async { [weak self] in
            guard let self = self else { return }
            let now = Date()
            let currentSize = self.appKeyFileSize(at: path)
            if self.inFlightApps[path] == nil {
                self.inFlightApps[path] = InFlightAppEntry(
                    path: path,
                    lastSize: currentSize,
                    unchangedCount: 0,
                    firstDetectedAt: now
                )
                self.scheduleInFlightCheck()
            }
        }
    }

    private func scheduleInFlightCheck() {
        inFlightCheckWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.evaluateInFlightApps()
        }
        inFlightCheckWorkItem = item
        queue.asyncAfter(deadline: .now() + 2.0, execute: item)
    }

    private func evaluateInFlightApps() {
        guard !inFlightApps.isEmpty else { return }
        let now = Date()
        var completedAny = false

        for (path, var entry) in inFlightApps {
            guard FileManager.default.fileExists(atPath: path) else {
                inFlightApps.removeValue(forKey: path)
                continue
            }

            // 60秒硬超时兜底，防止意外悬挂
            if now.timeIntervalSince(entry.firstDetectedAt) > 60.0 {
                inFlightApps.removeValue(forKey: path)
                completedAny = true
                continue
            }

            let currentSize = appKeyFileSize(at: path)
            // 军师加固点 2：若尺寸在持续增长，重置计数并顺延检测
            if currentSize > entry.lastSize {
                entry.lastSize = currentSize
                entry.unchangedCount = 0
                inFlightApps[path] = entry
            } else if currentSize > 0 && currentSize == entry.lastSize {
                entry.unchangedCount += 1
                inFlightApps[path] = entry
                // 连续 2 次（~4秒）尺寸稳定未变，且可执行文件已落地，判定拷贝完成
                if entry.unchangedCount >= 2 {
                    if let execPath = Bundle(path: path)?.executablePath,
                       FileManager.default.fileExists(atPath: execPath) {
                        inFlightApps.removeValue(forKey: path)
                        completedAny = true
                    }
                }
            } else {
                entry.lastSize = currentSize
                inFlightApps[path] = entry
            }
        }

        if completedAny {
            refreshIndex()
        }

        if !inFlightApps.isEmpty {
            scheduleInFlightCheck()
        }
    }

    private func appKeyFileSize(at path: String) -> Int64 {
        var total: Int64 = 0
        let infoPlist = (path as NSString).appendingPathComponent("Contents/Info.plist")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: infoPlist),
           let s = attrs[.size] as? Int64 {
            total += s
        }
        if let bundle = Bundle(path: path), let exec = bundle.executablePath {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: exec),
               let s = attrs[.size] as? Int64 {
                total += s
            }
        } else {
            let macosDir = (path as NSString).appendingPathComponent("Contents/MacOS")
            if let files = try? FileManager.default.contentsOfDirectory(atPath: macosDir) {
                for f in files {
                    let fp = (macosDir as NSString).appendingPathComponent(f)
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: fp),
                       let s = attrs[.size] as? Int64 {
                        total += s
                    }
                }
            }
        }
        return total
    }

    private func scheduleDebouncedRefresh() {
        debounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.refreshIndex()
        }
        debounceWorkItem = item
        // 防抖 2.0s，避免解压/PKG/Cask 写入过程中读取半包
        queue.asyncAfter(deadline: .now() + 2.0, execute: item)
    }

    /// Q-06: 线程安全节流刷新（加锁保护 lastRefreshDate 与 isScanInProgress，杜绝并发重入全量扫描）
    public func refreshIfStale(interval: TimeInterval = 30) {
        appsLock.lock()
        let shouldRefresh = !isScanInProgress && Date().timeIntervalSince(lastRefreshDate) > interval
        if shouldRefresh {
            lastRefreshDate = Date()
        }
        appsLock.unlock()

        if shouldRefresh {
            refreshIndex()
        }
    }

    public func refreshIndex(completion: (() -> Void)? = nil) {
        appsLock.lock()
        if isScanInProgress && completion == nil {
            appsLock.unlock()
            return
        }
        isScanInProgress = true
        lastRefreshDate = Date()
        appsLock.unlock()

        queue.async { [weak self] in
            guard let self = self else { return }
            var results: [IndexedApp] = []
            var visitedPaths = Set<String>()
            var visitedDirectories = Set<String>()

            let directoriesToScan = self.collectAppDirectories()

            for dir in directoriesToScan {
                guard FileManager.default.fileExists(atPath: dir) else { continue }
                self.scanDirectoryFast(
                    dir,
                    depth: 0,
                    maxDepth: AppConstants.appIndexScanDepth,
                    results: &results,
                    visitedPaths: &visitedPaths,
                    visitedDirectories: &visitedDirectories
                )
            }

            self.appsLock.lock()
            self.apps = results
            self.isScanInProgress = false
            self.lastRefreshDate = Date()
            self.appsLock.unlock()
            completion?()

            // 触发新安装应用自动入库
            ConfigManager.shared.handleAppIndexUpdated(apps: results)

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .atoolsAppIndexDidUpdate, object: nil)
            }
        }
    }

    private func collectAppDirectories() -> [String] {
        let home = NSHomeDirectory()
        return [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices/Applications",
            "/System/Library/CoreServices",
            "/System/Cryptexes/App/System/Applications",
            "\(home)/Applications",
            "/Applications/Setapp",
            "/opt/homebrew/Caskroom",
            "/usr/local/Caskroom",
            "\(home)/Library/Application Support/Steam/steamapps/common",
            "/System/Library/PreferencePanes",
            "/Library/PreferencePanes",
            "\(home)/Library/PreferencePanes"
        ]
    }

    /// Q-07 & 军师加固点 3：遍历目录时解析软链接并基于 NFC 规范化路径记录 visitedDirectories，彻底阻断目录符号链接环路
    private func scanDirectoryFast(
        _ dir: String,
        depth: Int,
        maxDepth: Int,
        results: inout [IndexedApp],
        visitedPaths: inout Set<String>,
        visitedDirectories: inout Set<String>
    ) {
        let canonicalDir = (dir as NSString).resolvingSymlinksInPath.precomposedStringWithCanonicalMapping
        guard visitedDirectories.insert(canonicalDir).inserted else { return }

        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }

        for item in contents {
            if item.hasPrefix(".") { continue }
            let fullPath = (dir as NSString).appendingPathComponent(item)

            if MetadataFileSearchBackend.isApplicationOrPrefPane(item) {
                let resolvedPath = (fullPath as NSString).resolvingSymlinksInPath.precomposedStringWithCanonicalMapping
                if !visitedPaths.contains(resolvedPath) {
                    visitedPaths.insert(resolvedPath)
                    autoreleasepool {
                        let baseName = (item as NSString).deletingPathExtension
                        var aliases: [String] = []

                        let fileURL = URL(fileURLWithPath: fullPath)
                        let resourceValues = try? fileURL.resourceValues(forKeys: [.localizedNameKey])
                        let lsName = resourceValues?.localizedName?.replacingOccurrences(of: ".app", with: "", options: .caseInsensitive)

                        if let ls = lsName, !ls.isEmpty && ls != baseName {
                            aliases.append(ls)
                        }

                        let metadata = AppMetadataReader.read(appURL: fileURL)
                        aliases.append(contentsOf: metadata.localizedNames)
                        if let disp = metadata.displayName, !disp.isEmpty { aliases.append(disp) }
                        if let bName = metadata.bundleName, !bName.isEmpty { aliases.append(bName) }

                        if let wellKnown = AppHotspotIndex.wellKnownAliases[baseName] {
                            aliases.append(contentsOf: wellKnown)
                        }

                        let primaryLocalizedName = aliases.first ?? lsName ?? baseName
                        let isCoreServicesDaemon = fullPath.contains("/System/Library/CoreServices") && !fullPath.contains("/System/Library/CoreServices/Applications")
                        let isExcluded = metadata.bundleIdentifier.map { AutoQuitManager.systemExcludedBundleIDs.contains($0) || $0 == "cc.atools.app" || $0 == "cc.atools.app.dev" } ?? true
                        let isPrefPane = (fullPath as NSString).pathExtension.caseInsensitiveCompare("prefPane") == .orderedSame
                        let isRegular = !isPrefPane && !metadata.isUIElement && !metadata.isBackgroundOnly && !isCoreServicesDaemon && !isExcluded && metadata.bundleIdentifier != nil && !(metadata.bundleIdentifier?.isEmpty ?? true)
                        let isShelfEligible = !isPrefPane && !metadata.isBackgroundOnly && !isCoreServicesDaemon && !isExcluded && metadata.bundleIdentifier != nil && !(metadata.bundleIdentifier?.isEmpty ?? true)

                        // 军师加固点 2：若发现未就绪的 .app 包（如 Info.plist 或二进制仍在拷贝），加入轮询追踪池
                        if (!isShelfEligible || metadata.bundleIdentifier == nil) && item.hasSuffix(".app") && !isCoreServicesDaemon && !isExcluded {
                            self.trackInFlightCandidate(path: fullPath)
                        }

                        let indexed = IndexedApp(
                            name: baseName,
                            localizedName: primaryLocalizedName,
                            path: fullPath,
                            bundleId: metadata.bundleIdentifier,
                            isRegularApp: isRegular,
                            isShelfEligible: isShelfEligible,
                            additionalAliases: aliases
                        )
                        results.append(indexed)
                    }
                }
            } else if depth < maxDepth {
                let itemURL = URL(fileURLWithPath: fullPath)
                let values = try? itemURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                // Q-07: 默认跳过子目录符号链接以防死循环与越界扫描
                if values?.isSymbolicLink == true {
                    continue
                }
                if values?.isDirectory == true {
                    let ext = (item as NSString).pathExtension.lowercased()
                    if ext != "app" && ext != "framework" && ext != "lproj" && ext != "prefpane" {
                        scanDirectoryFast(
                            fullPath,
                            depth: depth + 1,
                            maxDepth: maxDepth,
                            results: &results,
                            visitedPaths: &visitedPaths,
                            visitedDirectories: &visitedDirectories
                        )
                    }
                }
            }
        }
    }

    private static let wellKnownAliases: [String: [String]] = [
        "WeChat": ["微信"],
        "Finder": ["访达"],
        "Terminal": ["终端"],
        "Notes": ["备忘录"],
        "System Settings": ["系统设置", "设置"],
        "System Preferences": ["系统偏好设置", "偏好设置"],
        "Safari": ["Safari 浏览器", "浏览器"],
        "Music": ["音乐"],
        "Maps": ["地图"],
        "Calculator": ["计算器"],
        "Calendar": ["日历"],
        "Mail": ["邮件"],
        "Reminders": ["提醒事项"],
        "Photos": ["照片"],
        "TextEdit": ["文本编辑"],
        "Activity Monitor": ["活动监视器"],
        "Keychain Access": ["钥匙串访问", "钥匙串"],
        "Console": ["控制台"],
        "Disk Utility": ["磁盘工具"],
        "BaiduNetdisk": ["百度网盘", "网盘"],
        "Feishu": ["飞书"],
        "DingTalk": ["钉钉"],
        "WXWork": ["企业微信", "企微"],
        "TencentMeeting": ["腾讯会议"],
        "QQ": ["腾讯QQ"],
        "QQMusic": ["QQ音乐"],
        "NeteaseMusic": ["网易云音乐"]
    ]

    public var allApps: [IndexedApp] {
        appsLock.lock()
        defer { appsLock.unlock() }
        return apps
    }

    public var allRegularApps: [IndexedApp] {
        appsLock.lock()
        defer { appsLock.unlock() }
        return apps.filter { $0.isRegularApp }
    }

    public var allSelectableApps: [IndexedApp] {
        appsLock.lock()
        defer { appsLock.unlock() }

        let validApps = apps.filter { app in
            guard let bid = app.bundleId, !bid.isEmpty else { return false }
            guard (app.path as NSString).pathExtension.caseInsensitiveCompare("prefPane") != .orderedSame else { return false }
            guard !AutoQuitManager.systemExcludedBundleIDs.contains(bid) else { return false }
            guard bid != "cc.atools.app" && bid != "cc.atools.app.dev" else { return false }
            guard bid != "com.apple.controlcenter" && bid != "com.apple.wallpaper.agent" && bid != "com.apple.UserNotificationCenter" else { return false }
            let isCoreServicesDaemon = app.path.contains("/System/Library/CoreServices") && !app.path.contains("/System/Library/CoreServices/Applications")
            guard !isCoreServicesDaemon else { return false }
            return true
        }

        func pathPriority(_ path: String) -> Int {
            if path.hasPrefix("/Applications/") { return 5 }
            let home = NSHomeDirectory()
            if path.hasPrefix("\(home)/Applications/") { return 4 }
            if path.hasPrefix("/System/Applications/Utilities/") { return 3 }
            if path.hasPrefix("/System/Applications/") { return 2 }
            if path.hasPrefix("/System/Library/CoreServices/Applications/") { return 1 }
            return 0
        }

        var dedupedByBid: [String: IndexedApp] = [:]
        for app in validApps {
            guard let bid = app.bundleId else { continue }
            if let existing = dedupedByBid[bid] {
                if pathPriority(app.path) > pathPriority(existing.path) {
                    dedupedByBid[bid] = app
                }
            } else {
                dedupedByBid[bid] = app
            }
        }

        return dedupedByBid.values.sorted { $0.localizedName.localizedStandardCompare($1.localizedName) == .orderedAscending }
    }

    public func search(_ query: String) -> [IndexedApp] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        let snapshot: [IndexedApp]
        appsLock.lock()
        snapshot = self.apps
        appsLock.unlock()

        var exactMatches: [IndexedApp] = []
        var prefixMatches: [IndexedApp] = []
        var pinyinMatches: [IndexedApp] = []
        var fuzzyMatches: [IndexedApp] = []

        for app in snapshot {
            var matchedExact = false
            var matchedPrefix = false
            var matchedPinyin = false
            var matchedFuzzy = false

            for lower in app.lowercasedAliases {
                if lower == q {
                    matchedExact = true
                    break
                } else if lower.hasPrefix(q) {
                    matchedPrefix = true
                } else if lower.contains(q) {
                    matchedFuzzy = true
                }
            }

            if matchedExact {
                exactMatches.append(app)
                continue
            }

            for py in app.pinyins {
                if py == q || py.hasPrefix(q) {
                    matchedPinyin = true
                    break
                }
            }

            if !matchedPinyin {
                for abbr in app.pinyinAbbrs {
                    if abbr == q || abbr.hasPrefix(q) {
                        matchedPinyin = true
                        break
                    }
                }
            }

            if matchedPrefix {
                prefixMatches.append(app)
            } else if matchedPinyin {
                pinyinMatches.append(app)
            } else if matchedFuzzy {
                fuzzyMatches.append(app)
            }
        }

        return exactMatches + prefixMatches + pinyinMatches + fuzzyMatches
    }
}
