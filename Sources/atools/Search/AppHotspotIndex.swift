import Foundation
import AppKit
import Darwin

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

    private init() {
        refreshIndex()
        startWatchingAppDirectories()
    }

    deinit {
        for source in directorySources {
            source.cancel()
        }
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
