import Foundation
import CoreServices
import AppKit

public final class SpotlightBridge {
    public static let shared = SpotlightBridge()

    private let processLock = NSLock()
    private var activeProcess: Process?
    private var activePipe: Pipe?
    private let queue = DispatchQueue(label: "cc.atools.spotlight.process", qos: .userInitiated)
    private let queryIdLock = NSLock()
    private var _currentQueryId = UUID()

    /// Written on the main thread, read on the background queue for every enumerated file.
    private var currentQueryId: UUID {
        get {
            queryIdLock.lock()
            defer { queryIdLock.unlock() }
            return _currentQueryId
        }
        set {
            queryIdLock.lock()
            _currentQueryId = newValue
            queryIdLock.unlock()
        }
    }

    private init() {}

    /// 单个 CJK 字符（汉字/假名/谚文/扩展区）视为可独立检索的完整词。
    static func isCJK(_ ch: Character) -> Bool {
        let scalars = ch.unicodeScalars
        guard scalars.count == 1, let v = scalars.first?.value else { return false }
        return (0x4E00...0x9FFF).contains(v)    // CJK Unified Ideographs
            || (0x3400...0x4DBF).contains(v)    // Extension A
            || (0xF900...0xFAFF).contains(v)    // Compatibility Ideographs
            || (0x3040...0x30FF).contains(v)    // Hiragana & Katakana
            || (0xAC00...0xD7AF).contains(v)    // Hangul Syllables
            || (0x20000...0x3FFFF).contains(v)  // Extension B+
    }

    private func terminateActiveProcess() {
        processLock.lock()
        if let p = activeProcess, p.isRunning {
            p.terminate()
        }
        activeProcess = nil
        if let pipe = activePipe {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
        activePipe = nil
        processLock.unlock()
    }

    public func searchFiles(matching queryText: String, limit: Int = 60, filter: SearchTypeFilter = .all, completion: @escaping ([SearchResult]) -> Void) {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            DispatchQueue.main.async {
                completion([])
            }
            return
        }

        if filter == .application {
            // 应用分类直接由 Layer 1 AppHotspotIndex 闪电直出，跳过文件全盘检索
            DispatchQueue.main.async {
                completion([])
            }
            return
        }

        // The hot-folder snapshot can block on an in-progress rebuild (up to
        // 0.3s) and MDQuery scoring is CPU/XPC heavy: both belong off the main
        // thread. Typing a query like "how" used to freeze the UI because all
        // of this ran on the main run loop.
        DispatchQueue.global(qos: .userInitiated).async {
            let snapshot = self.hotFilesSnapshot(waitingUpTo: 0.3)

            // 热目录：先按类型过滤和匹配档位筛+排序（便宜），截取 limit 个后才补读最近打开时间
            //（kMDItemLastUsedDate 每条约 0.3ms XPC），再算上新鲜度得最终分。
            var hotCandidates: [(file: HotFile, base: Int)] = []
            hotCandidates.reserveCapacity(64)
            for file in snapshot {
                if filter != .all && !filter.matches(filename: file.name, isDirectory: file.isDirectory) {
                    continue
                }
                var base = SearchRanking.nameTier(name: file.name, query: trimmed) ?? 0
                let pinyin = SearchRanking.pinyinTier(pinyinFull: file.pinyinFull,
                                                      pinyinAbbr: file.pinyinAbbr,
                                                      query: trimmed)
                base = max(base, pinyin)
                guard base > 0 else { continue }
                hotCandidates.append((file, base))
            }
            hotCandidates.sort { $0.base > $1.base }

            var hotResults: [SearchResult] = []
            hotResults.reserveCapacity(min(hotCandidates.count, limit))
            for candidate in hotCandidates.prefix(limit) {
                let file = candidate.file
                let lastUsed = Self.lastUsedDate(forPath: file.path)
                let path = file.path
                hotResults.append(SearchResult(
                    title: file.name, subtitle: path, path: path,
                    type: file.isDirectory ? .folder : .file,
                    score: SearchRanking.finalScore(baseTier: candidate.base, path: path,
                                                    modified: file.modified, lastUsed: lastUsed),
                    action: { LauncherExecutor.open(path: path) }))
            }

            // 分层选取全盘检索作用域：
            // - ≥2 字符或单个 CJK 字：全盘（kMDQueryScopeComputer）
            // - 单个 ASCII 字符：限定在热目录内 —— 命中量可控（实测 45-240ms），
            //   且完整覆盖目录全深度（快照只到 3 层），补上“单字符搜不到快照外文件”的空档
            let scope: MetadataFileSearchBackend.ScopeTarget
            if trimmed.count >= 2 || (trimmed.first.map { Self.isCJK($0) } ?? false) {
                scope = .computer
            } else {
                scope = .directories(self.hotFolderURLs())
            }

            MetadataFileSearchBackend.shared.search(matching: trimmed, limit: limit, scope: scope, filter: filter) { metadataResults in
                // 归并（方案 A）：热目录与全盘用同一套打分，按分数全局降序；
                // 此前是拼接（热目录永远在前），全盘的精确命中会被热目录弱命中压住。
                var merged: [SearchResult] = []
                var seenPaths = Set<String>()
                let sorted = (hotResults + metadataResults).sorted { $0.score > $1.score }
                for result in sorted {
                    guard let path = result.path, !seenPaths.contains(path) else { continue }
                    seenPaths.insert(path)
                    merged.append(result)
                    if merged.count >= limit { break }
                }
                let final = merged
                // Deliver on main: the coordinator's generation checks and
                // result storage are main-thread state.
                DispatchQueue.main.async {
                    completion(final)
                }
            }
        }
    }

    // MARK: - Hot folder snapshot

    /// 默认热目录（相对家目录）。快照与单字符 MDQuery 作用域共用同一列表。
    static let defaultHotFolders = ["Downloads", "Desktop", "Documents"]

    /// 用户自定义热目录（绝对路径）。由 ConfigManager 在变更时与初始化时推送，
    /// 读写都在 hotCacheCondition 锁内——后台枚举/查询绝不直接读主线程的配置对象。
    private var extraFolders: [String] = []

    /// ConfigManager 变更自定义热目录后推送；随后应调用 dropHotFolderCache()
    /// 让下次搜索按新列表重建快照。
    public func setExtraHotFolders(_ paths: [String]) {
        hotCacheCondition.lock()
        extraFolders = paths
        hotCacheCondition.unlock()
    }

    /// 所有热目录（默认在前，自定义在后）。key 用绝对路径，避免同名目录冲突。
    static func hotFolderEntries(extraFolders: [String]) -> [(key: String, url: URL)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var entries = defaultHotFolders.map { name -> (key: String, url: URL) in
            let url = home.appendingPathComponent(name)
            return (key: url.path, url: url)
        }
        entries.append(contentsOf: extraFolders.map { (key: $0, url: URL(fileURLWithPath: $0)) })
        return entries
    }

    private func hotFolderEntries() -> [(key: String, url: URL)] {
        hotCacheCondition.lock()
        let extra = extraFolders
        hotCacheCondition.unlock()
        return Self.hotFolderEntries(extraFolders: extra)
    }

    private func hotFolderURLs() -> [URL] {
        hotFolderEntries().map(\.url)
    }

    // MARK: - Pinyin matching (热目录文件名拼音/首字母匹配)

    /// 热目录命中后的最近打开时间（仅对已命中的少量文件调用，≤limit 次 XPC）。
    private static func lastUsedDate(forPath path: String) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    private static let pinyinCacheLock = NSLock()
    private static var pinyinCache: [String: (full: String, abbr: String)] = [:]

    /// 文件名 → 拼音形态。
    /// Han-Latin 转换约 0.1ms/条（25k 条 ≈ 2.4s），所以只在快照重建时调用，
    /// 按文件名缓存：重建时只有新文件名会真正转换，旧的一律命中缓存。
    static func pinyinForms(for name: String) -> (full: String, abbr: String) {
        pinyinCacheLock.lock()
        if let hit = pinyinCache[name] {
            pinyinCacheLock.unlock()
            return hit
        }
        pinyinCacheLock.unlock()

        // Han-Latin：按音节切分且多音字按词组正确（重庆→chóng、银行→yín háng）；
        // Latin-ASCII：去声调（bào → bao）。
        let han = name.applyingTransform(StringTransform(rawValue: "Han-Latin"), reverse: false) ?? name
        let ascii = han.applyingTransform(StringTransform(rawValue: "Latin-ASCII"), reverse: false) ?? han
        // 音节/拉丁词按非字母数字切分：
        // "mao jing fei_kai ti bao gao. docx" → [mao,jing,fei,kai,ti,bao,gao,docx]
        let tokens = ascii.lowercased().split { !$0.isLetter && !$0.isNumber }
        let forms = (full: tokens.joined(),
                     abbr: tokens.compactMap { $0.first.map(String.init) }.joined())

        pinyinCacheLock.lock()
        if pinyinCache.count > 120_000 { pinyinCache.removeAll() }
        pinyinCache[name] = forms
        pinyinCacheLock.unlock()
        return forms
    }

    private struct HotFile {
        let name: String
        let path: String
        let isDirectory: Bool
        /// 快照枚举时顺手取的修改时间（新鲜度打分用，零额外 IO）
        let modified: Date?
        /// 拼音匹配形态（快照重建时后台计算，缓存复用）：
        /// full = 音节拼接（"kaitibaogao"），abbr = 音节首字母（"ktbg"）
        let pinyinFull: String
        let pinyinAbbr: String
    }

    private let hotCacheQueue = DispatchQueue(label: "cc.atools.spotlight.hotcache", qos: .utility)
    private let hotCacheCondition = NSCondition()
    private var hotCache: [String: [HotFile]] = [:]
    private var hotCacheDate = Date.distantPast
    private var hotCacheBuildStarted = Date.distantPast
    private var hotFolderUpdated: [String: Date] = [:]
    private var isBuildingHotCache = false

    /// Rebuilds the hot-folder snapshot in the background when it is older than `maxAge`.
    /// Folders are published one at a time, so a fast folder (Downloads) is searchable while a
    /// slow one (e.g. iCloud Desktop) is still being listed.
    public func warmHotFolderCache(maxAge: TimeInterval = 30) {
        hotCacheCondition.lock()
        let isStale = Date().timeIntervalSince(hotCacheDate) > maxAge
        guard isStale, !isBuildingHotCache else {
            hotCacheCondition.unlock()
            return
        }
        isBuildingHotCache = true
        hotCacheBuildStarted = Date()
        hotCacheCondition.unlock()

        hotCacheQueue.async { [weak self] in
            guard let self = self else { return }
            for entry in self.hotFolderEntries() {
                let files = self.listHotFolder(entry.url)
                self.hotCacheCondition.lock()
                self.hotCache[entry.key] = files
                self.hotFolderUpdated[entry.key] = Date()
                self.hotCacheCondition.broadcast()
                self.hotCacheCondition.unlock()
            }
            self.hotCacheCondition.lock()
            self.hotCacheDate = Date()
            self.isBuildingHotCache = false
            self.hotCacheCondition.broadcast()
            self.hotCacheCondition.unlock()
        }
    }

    private func listHotFolder(_ folder: URL) -> [HotFile] {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [HotFile] = []
        for case let fileURL as URL in enumerator {
            // Worst-case bound: on machines with very large Downloads trees this
            // snapshot alone can reach many MB of retained name/path strings.
            // Full-disk results still come from the Spotlight metadata backend.
            if files.count >= AppConstants.hotFolderEntryCap {
                break
            }
            // Stop descending at the depth limit instead of listing one level too deep.
            if enumerator.level >= AppConstants.spotlightHotFolderDepth {
                enumerator.skipDescendants()
            }
            let filename = fileURL.lastPathComponent
            if SearchExclusionEngine.shared.shouldSkipDescendants(folderName: filename, path: fileURL.path) {
                enumerator.skipDescendants()
                continue
            }
            if filename.hasPrefix(".") || filename.hasSuffix(".app") || SearchExclusionEngine.shared.isExcluded(path: fileURL.path) {
                continue
            }
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            let isDir = values?.isDirectory ?? false
            let modified = values?.contentModificationDate

            var displayOrCleanName = filename
            if filename.hasSuffix(".localized") {
                let dn = FileManager.default.displayName(atPath: fileURL.path)
                displayOrCleanName = (!dn.isEmpty && !dn.hasSuffix(".localized"))
                    ? dn
                    : String(filename.dropLast(".localized".count))
            }

            // 拼音形态按文件名缓存，重建快照时只有新文件名会真正转换。
            let pinyin = Self.pinyinForms(for: displayOrCleanName)
            files.append(HotFile(name: displayOrCleanName, path: fileURL.path, isDirectory: isDir,
                                 modified: modified,
                                 pinyinFull: pinyin.full, pinyinAbbr: pinyin.abbr))
        }
        return files
    }

    /// Returns the current snapshot, briefly waiting for an in-progress rebuild.
    private func hotFilesSnapshot(waitingUpTo timeout: TimeInterval) -> [HotFile] {
        warmHotFolderCache()
        let entries = hotFolderEntries()
        let deadline = Date().addingTimeInterval(timeout)
        hotCacheCondition.lock()
        defer { hotCacheCondition.unlock() }
        // Wait for the rebuild's first folder listing (usually milliseconds) so just-downloaded
        // files show up; slower folders are used from the previous snapshot meanwhile.
        let firstKey = entries.first?.key ?? ""
        while isBuildingHotCache,
              // ① 首个目录（默认最先发布，通常毫秒级）刷到本次构建，保证刚下载的文件可搜；
              // ② 任何目录尚无快照（例如刚添加的自定义目录）时也必须等——
              //    否则添加后的首次搜索会因为新目录还没枚举完而搜不到。
              ((hotFolderUpdated[firstKey] ?? .distantPast) < hotCacheBuildStarted
                || entries.contains { hotCache[$0.key] == nil }),
              hotCacheCondition.wait(until: deadline) {}
        return entries.flatMap { hotCache[$0.key] ?? [] }
    }

    public func stop() {
        MetadataFileSearchBackend.shared.cancel()
        currentQueryId = UUID()
        terminateActiveProcess()
    }

    /// Called from the memory anneal. The snapshot is warmed again on the next
    /// panel show (maxAge=5s) and the next search (maxAge=30s), so dropping it
    /// while idle costs only a background re-listing and returns its strings.
    public func dropHotFolderCache() {
        hotCacheCondition.lock()
        hotCache.removeAll()
        hotFolderUpdated.removeAll()
        hotCacheDate = Date.distantPast
        hotCacheBuildStarted = Date.distantPast
        hotCacheCondition.broadcast()
        hotCacheCondition.unlock()
        // 拼音缓存同样属于可重建的缓存态内存，退火时一并归还。
        Self.pinyinCacheLock.lock()
        Self.pinyinCache.removeAll()
        Self.pinyinCacheLock.unlock()
    }
}
