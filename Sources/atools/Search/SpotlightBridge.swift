import Foundation
import CoreServices
import AppKit

public final class SpotlightBridge {
    public static let shared = SpotlightBridge()

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

    /// 军师加固点 2：后台检索线程统一产出轻量不可变 Sendable 的 RawSearchResultPayload
    public func searchFilePayloads(
        matching queryText: String,
        limit: Int = 60,
        filter: SearchTypeFilter = .all,
        completion: @escaping @Sendable ([RawSearchResultPayload]) -> Void
    ) {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeLimit = max(AppConstants.searchResultLimitRange.lowerBound, min(AppConstants.searchResultLimitRange.upperBound, limit))

        guard !trimmed.isEmpty else {
            DispatchQueue.main.async {
                completion([])
            }
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let snapshot = self.hotFilesSnapshot(waitingUpTo: 0.3)

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

            // Q-08: 扩大粗排候选池（至少 max(safeLimit * 3, 100)），全量计算新鲜度得分后再做最终排序截断
            let coarsePoolLimit = min(hotCandidates.count, max(safeLimit * 3, 100))
            var hotPayloads: [RawSearchResultPayload] = []
            hotPayloads.reserveCapacity(coarsePoolLimit)
            for candidate in hotCandidates.prefix(coarsePoolLimit) {
                let file = candidate.file
                let lastUsed = Self.lastUsedDate(forPath: file.path)
                let path = file.path
                let isApp = MetadataFileSearchBackend.isApplicationOrPrefPane(path)
                let resultType: SearchResultType = isApp ? .application : (file.isDirectory ? .folder : .file)
                let displayName = isApp ? (file.name as NSString).deletingPathExtension : file.name
                let finalScore = SearchRanking.finalScore(
                    baseTier: candidate.base,
                    path: path,
                    modified: file.modified,
                    lastUsed: lastUsed
                )
                hotPayloads.append(RawSearchResultPayload(
                    title: displayName,
                    subtitle: path,
                    path: path,
                    type: resultType,
                    score: finalScore
                ))
            }
            hotPayloads.sort { $0.score > $1.score }
            if hotPayloads.count > safeLimit {
                hotPayloads = Array(hotPayloads.prefix(safeLimit))
            }
            let immutableHotPayloads = hotPayloads

            let scope: MetadataFileSearchBackend.ScopeTarget
            if trimmed.count >= 2 || (trimmed.first.map { Self.isCJK($0) } ?? false) {
                scope = .computer
            } else {
                scope = .directories(self.hotFolderURLs())
            }

            MetadataFileSearchBackend.shared.searchPayloads(matching: trimmed, limit: safeLimit, scope: scope, filter: filter) { metadataPayloads in
                var merged: [RawSearchResultPayload] = []
                var seenPaths = Set<String>()
                let sorted = (immutableHotPayloads + metadataPayloads).sorted { $0.score > $1.score }
                for payload in sorted {
                    guard let path = payload.path else { continue }
                    let canonicalPath = path.precomposedStringWithCanonicalMapping
                    guard !seenPaths.contains(canonicalPath) else { continue }
                    seenPaths.insert(canonicalPath)
                    merged.append(payload)
                    if merged.count >= safeLimit { break }
                }
                let finalPayloads = merged
                DispatchQueue.main.async {
                    completion(finalPayloads)
                }
            }
        }
    }

    public func searchFiles(
        matching queryText: String,
        limit: Int = 60,
        filter: SearchTypeFilter = .all,
        completion: @escaping ([SearchResult]) -> Void
    ) {
        searchFilePayloads(matching: queryText, limit: limit, filter: filter) { payloads in
            // 已在 DispatchQueue.main 上回调，安全组装 SearchResult
            let materialized = payloads.map { $0.materializeSearchResult() }
            completion(materialized)
        }
    }

    // MARK: - Hot folder snapshot

    static let defaultHotFolders = ["Downloads", "Desktop", "Documents"]

    private var extraFolders: [String] = []

    /// Q-05: 变更热目录时同步递增版本代次号 hotCacheGeneration，防止在途旧扫描结果覆盖新配置
    public func setExtraHotFolders(_ paths: [String]) {
        hotCacheCondition.lock()
        extraFolders = paths
        hotCacheGeneration &+= 1
        isBuildingHotCache = false
        hotCacheCondition.broadcast()
        hotCacheCondition.unlock()
    }

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

    private static func lastUsedDate(forPath path: String) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    private static let pinyinCacheLock = NSLock()
    private static var pinyinCache: [String: (full: String, abbr: String)] = [:]

    static func pinyinForms(for name: String) -> (full: String, abbr: String) {
        pinyinCacheLock.lock()
        if let hit = pinyinCache[name] {
            pinyinCacheLock.unlock()
            return hit
        }
        pinyinCacheLock.unlock()

        let han = name.applyingTransform(StringTransform(rawValue: "Han-Latin"), reverse: false) ?? name
        let ascii = han.applyingTransform(StringTransform(rawValue: "Latin-ASCII"), reverse: false) ?? han
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
        let modified: Date?
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
    /// Q-05: 热目录缓存版本代次号，每次 dropHotFolderCache / setExtraHotFolders 时递增
    private var hotCacheGeneration: UInt64 = 0

    public func warmHotFolderCache(maxAge: TimeInterval = 30) {
        hotCacheCondition.lock()
        let isStale = Date().timeIntervalSince(hotCacheDate) > maxAge
        guard isStale, !isBuildingHotCache else {
            hotCacheCondition.unlock()
            return
        }
        isBuildingHotCache = true
        hotCacheBuildStarted = Date()
        let capturedGeneration = hotCacheGeneration
        let entriesToScan = Self.hotFolderEntries(extraFolders: extraFolders)
        hotCacheCondition.unlock()

        hotCacheQueue.async { [weak self] in
            guard let self = self else { return }
            for entry in entriesToScan {
                self.hotCacheCondition.lock()
                let genValidBefore = (self.hotCacheGeneration == capturedGeneration)
                self.hotCacheCondition.unlock()
                guard genValidBefore else { return }

                let files = self.listHotFolder(entry.url)

                self.hotCacheCondition.lock()
                guard self.hotCacheGeneration == capturedGeneration else {
                    self.hotCacheCondition.broadcast()
                    self.hotCacheCondition.unlock()
                    return
                }
                self.hotCache[entry.key] = files
                self.hotFolderUpdated[entry.key] = Date()
                self.hotCacheCondition.broadcast()
                self.hotCacheCondition.unlock()
            }
            self.hotCacheCondition.lock()
            if self.hotCacheGeneration == capturedGeneration {
                self.hotCacheDate = Date()
                self.isBuildingHotCache = false
            }
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
            if files.count >= AppConstants.hotFolderEntryCap {
                break
            }
            if enumerator.level >= AppConstants.spotlightHotFolderDepth {
                enumerator.skipDescendants()
            }
            let filename = fileURL.lastPathComponent
            if SearchExclusionEngine.shared.shouldSkipDescendants(folderName: filename, path: fileURL.path) {
                enumerator.skipDescendants()
                continue
            }
            if filename.hasPrefix(".") || MetadataFileSearchBackend.isApplicationOrPrefPane(filename) || SearchExclusionEngine.shared.isExcluded(path: fileURL.path) {
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

            let pinyin = Self.pinyinForms(for: displayOrCleanName)
            files.append(HotFile(name: displayOrCleanName, path: fileURL.path, isDirectory: isDir,
                                 modified: modified,
                                 pinyinFull: pinyin.full, pinyinAbbr: pinyin.abbr))
        }
        return files
    }

    private func hotFilesSnapshot(waitingUpTo timeout: TimeInterval) -> [HotFile] {
        warmHotFolderCache()
        let entries = hotFolderEntries()
        let deadline = Date().addingTimeInterval(timeout)
        hotCacheCondition.lock()
        defer { hotCacheCondition.unlock() }
        let firstKey = entries.first?.key ?? ""
        while isBuildingHotCache,
              ((hotFolderUpdated[firstKey] ?? .distantPast) < hotCacheBuildStarted
                || entries.contains { hotCache[$0.key] == nil }),
              hotCacheCondition.wait(until: deadline) {}
        return entries.flatMap { hotCache[$0.key] ?? [] }
    }

    public func stop() {
        MetadataFileSearchBackend.shared.cancel()
    }

    /// Q-05: 丢弃热目录缓存时递增 hotCacheGeneration 并重置构建标志，令后台正在进行的旧配置枚举作废
    public func dropHotFolderCache() {
        hotCacheCondition.lock()
        hotCacheGeneration &+= 1
        isBuildingHotCache = false
        hotCache.removeAll()
        hotFolderUpdated.removeAll()
        hotCacheDate = Date.distantPast
        hotCacheBuildStarted = Date.distantPast
        hotCacheCondition.broadcast()
        hotCacheCondition.unlock()
        Self.pinyinCacheLock.lock()
        Self.pinyinCache.removeAll()
        Self.pinyinCacheLock.unlock()
    }
}
