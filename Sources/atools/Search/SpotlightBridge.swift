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

    public func searchFiles(matching queryText: String, limit: Int = 60, completion: @escaping ([SearchResult]) -> Void) {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
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
            let hot = self.hotFilesSnapshot(waitingUpTo: 0.3).compactMap { file -> SearchResult? in
                guard let tier = Self.hotMatchTier(name: file.name,
                                                   pinyinFull: file.pinyinFull,
                                                   pinyinAbbr: file.pinyinAbbr,
                                                   query: trimmed) else { return nil }
                let path = file.path
                return SearchResult(title: file.name, subtitle: path, path: path,
                                    type: file.isDirectory ? .folder : .file,
                                    score: tier,
                                    action: { LauncherExecutor.open(path: path) })
            }

            // 分层选取全盘检索作用域：
            // - ≥2 字符或单个 CJK 字：全盘（kMDQueryScopeComputer）
            // - 单个 ASCII 字符：限定在热目录内 —— 命中量可控（实测 45-240ms），
            //   且完整覆盖目录全深度（快照只到 3 层），补上“单字符搜不到快照外文件”的空档
            let scope: MetadataFileSearchBackend.ScopeTarget
            if trimmed.count >= 2 || (trimmed.first.map { Self.isCJK($0) } ?? false) {
                scope = .computer
            } else {
                scope = .directories(Self.hotFolderURLs())
            }

            MetadataFileSearchBackend.shared.search(matching: trimmed, limit: limit, scope: scope) { metadataResults in
                var merged = Array(hot.prefix(limit))
                for result in metadataResults where !merged.contains(where: { $0.path == result.path }) {
                    merged.append(result)
                }
                let final = Array(merged.prefix(limit))
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

    static func hotFolderURLs() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return defaultHotFolders.map { home.appendingPathComponent($0) }
    }

    // MARK: - Pinyin matching (热目录文件名拼音/首字母匹配)

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

    /// 热目录命中分层打分（也为后续热目录/全盘统一归并排序准备）。
    /// 返回 nil = 未命中。
    static func hotMatchTier(name: String, pinyinFull: String, pinyinAbbr: String, query: String) -> Int? {
        let q = query.lowercased()
        if name.localizedCaseInsensitiveContains(query) {
            let lowerName = name.lowercased()
            if lowerName == q { return 130 }        // 文件名完全相等
            if lowerName.hasPrefix(q) { return 120 } // 前缀
            return 110                              // 包含
        }
        // 拼音匹配至少 2 字符（单字符靠文件名匹配 + 限定作用域的 MDQuery 覆盖，
        // 否则首字母表里每个文件都会被单字母命中）
        guard q.count >= 2 else { return nil }
        let qCompact = q.replacingOccurrences(of: " ", with: "")
        guard !qCompact.isEmpty else { return nil }
        if pinyinFull == qCompact { return 108 }      // 全拼音相等（kaitibaogao）
        if pinyinFull.hasPrefix(qCompact) { return 104 }
        if pinyinFull.contains(qCompact) { return 100 }
        if pinyinAbbr.hasPrefix(qCompact) { return 96 }  // 首字母前缀（ktbg）
        if pinyinAbbr.contains(qCompact) { return 92 }
        return nil
    }

    private struct HotFile {
        let name: String
        let path: String
        let isDirectory: Bool
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
            let home = FileManager.default.homeDirectoryForCurrentUser
            for folder in Self.defaultHotFolders {
                let files = self.listHotFolder(home.appendingPathComponent(folder))
                self.hotCacheCondition.lock()
                self.hotCache[folder] = files
                self.hotFolderUpdated[folder] = Date()
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
            includingPropertiesForKeys: [.isDirectoryKey],
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
            if filename == "node_modules" || filename == "DerivedData" || filename == ".git" {
                enumerator.skipDescendants()
                continue
            }
            if filename.hasPrefix(".") || filename.hasSuffix(".app") { continue }
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            // 拼音形态按文件名缓存，重建快照时只有新文件名会真正转换。
            let pinyin = Self.pinyinForms(for: filename)
            files.append(HotFile(name: filename, path: fileURL.path, isDirectory: isDir,
                                 pinyinFull: pinyin.full, pinyinAbbr: pinyin.abbr))
        }
        return files
    }

    /// Returns the current snapshot, briefly waiting for an in-progress rebuild.
    private func hotFilesSnapshot(waitingUpTo timeout: TimeInterval) -> [HotFile] {
        warmHotFolderCache()
        let deadline = Date().addingTimeInterval(timeout)
        hotCacheCondition.lock()
        defer { hotCacheCondition.unlock() }
        // Wait for the rebuild's first folder listing (usually milliseconds) so just-downloaded
        // files show up; slower folders are used from the previous snapshot meanwhile.
        let firstFolder = Self.defaultHotFolders.first ?? ""
        while isBuildingHotCache,
              (hotFolderUpdated[firstFolder] ?? .distantPast) < hotCacheBuildStarted,
              hotCacheCondition.wait(until: deadline) {}
        return Self.defaultHotFolders.flatMap { hotCache[$0] ?? [] }
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
