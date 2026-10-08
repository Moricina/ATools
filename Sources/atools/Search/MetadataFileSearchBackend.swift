import Foundation
import CoreServices
import UniformTypeIdentifiers

/// Full-disk file search backed by CoreServices `MDQuery`.
///
/// The previous implementation used `NSMetadataQuery`, which must live on the
/// main run loop: its `DidFinishGathering` handler read `NSMetadataItem`
/// attributes on the main thread, and every uncached attribute read is a
/// **synchronous XPC round-trip to the mds daemon** (`mach_msg`), plus one
/// `stat()` per item for the directory check. A query like `CONTAINS "how"`
/// matches tens of thousands of filenames, so typing froze the UI (sampled:
/// 70% of main-thread time inside this file).
///
/// `MDQuery` executes synchronously on a background serial queue, declares the
/// attributes it will read up-front so they arrive batched with the results
/// (in-memory reads instead of per-item XPC), and coalesces so only the newest
/// request ever runs a query.
public final class MetadataFileSearchBackend: NSObject {
    public static let shared = MetadataFileSearchBackend()

    /// 查询范围。`.directories` 用于单字符查询：命中量仍可控，但完整覆盖目录全深度
    /// （热目录快照只到 3 层，MDQuery 范围内到任意深度）。
    public enum ScopeTarget {
        case computer
        case directories([URL])
    }

    /// Serial queue: at most one synchronous MDQuery runs at a time.
    private let queue = DispatchQueue(label: "cc.atools.metadata.mdquery", qos: .userInitiated)
    private let idLock = NSLock()
    private var currentSearchID = UUID()

    /// Prefetched alongside every result.
    ///
    /// 性能关键：`kMDItemPath` 是免费的（随每条结果自带，实测 0.004ms/条），
    /// 而 FSName/ContentType/日期即使声明了预取，每条仍要一次 ~0.28ms 的同步 XPC。
    /// 所以大循环只读 path（文件名直接从 path 截取），属性只在 Top-N 第二轮里补读。
    private static let prefetchAttributes: [CFString] = [
        kMDItemPath!
    ]

    /// 构建 Spotlight 查询谓词。
    ///
    /// **MDQueryCreate 的谓词语言不支持 NSPredicate 的 `CONTAINS`/`LIKE`/`BEGINSWITH`**
    /// （对它们直接返回 NULL，历史 bug：全盘检索静默返回空）。只能用通配符形式：
    /// `kMDItemFSName == '*<text>*'cd`（c=忽略大小写 d=忽略变音符）。
    /// 查询串中的 `\ ' * ?` 是元字符/转义符，必须按字面量转义。
    static func predicateText(matching text: String, filter: SearchTypeFilter = .all) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count + 4)
        for ch in text {
            switch ch {
            case "\\": escaped += "\\\\"   // 反斜杠先转
            case "'":  escaped += "\\'"
            case "*":  escaped += "\\*"    // 防止用户输入变成通配符（如 a*b 扫全盘）
            case "?":  escaped += "\\?"
            default:   escaped.append(ch)
            }
        }
        let basePred = "(kMDItemFSName == '*\(escaped)*'cd || kMDItemDisplayName == '*\(escaped)*'cd)"
        if let typePred = filter.mdQueryContentTypePredicate {
            return "(\(basePred) && \(typePred))"
        }
        return basePred
    }

    public func search(matching text: String, limit: Int,
                       scope: ScopeTarget = .computer,
                       filter: SearchTypeFilter = .all,
                       completion: @escaping ([SearchResult]) -> Void) {
        let searchID = UUID()
        idLock.lock()
        currentSearchID = searchID
        idLock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            // Coalesce: a newer request arrived while this one was queued.
            guard self.isCurrent(searchID) else { return }

            let results = self.execute(predicateText: text, limit: limit, scope: scope, filter: filter)

            // Drop results that were superseded while the query ran.
            guard self.isCurrent(searchID) else { return }
            completion(results)
        }
    }

    public func cancel() {
        idLock.lock()
        currentSearchID = UUID()
        idLock.unlock()
    }

    private func isCurrent(_ id: UUID) -> Bool {
        idLock.lock()
        defer { idLock.unlock() }
        return currentSearchID == id
    }

    private func execute(predicateText text: String, limit: Int, scope: ScopeTarget, filter: SearchTypeFilter = .all) -> [SearchResult] {
        let predicate = Self.predicateText(matching: text, filter: filter)

        guard let query = MDQueryCreate(kCFAllocatorDefault, predicate as CFString,
                                        Self.prefetchAttributes as CFArray, [] as CFArray) else {
            runtimeLog("[MDQuery] predicate not parsable: \(predicate)")
            return []
        }

        switch scope {
        case .computer:
            MDQuerySetSearchScope(query, [kMDQueryScopeComputer!] as CFArray, 0)
        case .directories(let urls):
            // 纯目录 URL 数组（混入 Scope 字符串会被当作全盘处理）。
            MDQuerySetSearchScope(query, urls.map { $0 as CFURL } as CFArray, 0)
        }
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else {
            runtimeLog("[MDQuery] execute failed: \(predicate)")
            return []
        }

        let count = MDQueryGetResultCount(query)
        // 第一轮（全量）：只读 kMDItemPath —— 免费；其余属性每条 0.28ms XPC。
        // 旧实现在这一轮就读 5 个属性，扫 6801 条要 8 秒；同样数据现在 ~70ms。
        var candidates: [Candidate] = []
        candidates.reserveCapacity(min(Int(count), limit * 8))

        var localizedResolutionsCount = 0
        let maxLocalizedResolutions = 64 // XPC 熔断上限

        for index in 0..<count {
            guard let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()

            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String,
                  !path.isEmpty,
                  !path.hasSuffix(".app"),
                  !Self.isExcluded(path) else { continue }

            let rawName = (path as NSString).lastPathComponent
            var resolvedName = rawName

            // 针对 .localized 目录，去除末尾生硬物理后缀参与比对
            let cleanDiskName = rawName.hasSuffix(".localized")
                ? String(rawName.dropLast(".localized".count))
                : rawName

            var tier = SearchRanking.nameTier(name: cleanDiskName, query: text)

            // 物理文件名未命中，说明是由 kMDItemDisplayName 命中的本地化条目
            if tier == nil && localizedResolutionsCount < maxLocalizedResolutions {
                localizedResolutionsCount += 1
                let dn = (MDItemCopyAttribute(item, kMDItemDisplayName) as? String)
                    ?? FileManager.default.displayName(atPath: path)
                if !dn.isEmpty {
                    resolvedName = dn
                    tier = SearchRanking.nameTier(name: dn, query: text)
                }
            } else if rawName.hasSuffix(".localized") {
                // 物理文件名命中，但为了界面美观，尝试获取 display name
                let dn = FileManager.default.displayName(atPath: path)
                if !dn.isEmpty && !dn.hasSuffix(".localized") {
                    resolvedName = dn
                } else {
                    resolvedName = cleanDiskName
                }
            }

            let baseTier = tier ?? SearchRanking.tierContains
            let baseScore = baseTier - SearchRanking.depthPenalty(path: path)

            candidates.append(Candidate(
                baseScore: baseScore,
                name: resolvedName, path: path, item: item))
        }

        // 第二轮：只为 Top-N 补读 ContentType/日期（N×0.28ms ≈ 17ms），细化打分。
        let top = candidates.sorted { $0.baseScore > $1.baseScore }.prefix(max(1, limit))
        var finalized: [(score: Int, name: String, path: String, isFolder: Bool)] = []
        finalized.reserveCapacity(top.count)
        for c in top {
            let modified = MDItemCopyAttribute(c.item, kMDItemContentModificationDate) as? Date
            let lastUsed = MDItemCopyAttribute(c.item, kMDItemLastUsedDate) as? Date
            let contentType = MDItemCopyAttribute(c.item, kMDItemContentType) as? String
            let isFolder = contentType.map { UTType($0)?.conforms(to: .folder) ?? false } ?? false

            let score = c.baseScore + SearchRanking.freshnessScore(modified: modified, lastUsed: lastUsed)
            finalized.append((score, c.name, c.path, isFolder))
        }

        let best = finalized.sorted { $0.score > $1.score }
        return best.map { c in
            let path = c.path
            return SearchResult(title: c.name, subtitle: path, path: path,
                                type: c.isFolder ? .folder : .file,
                                score: c.score,
                                action: { LauncherExecutor.open(path: path) })
        }
    }

    private struct Candidate {
        let baseScore: Int
        let name: String
        let path: String
        /// Top-N 复审阶段读属性用；ARC 持有到 execute() 结束（先于 query 释放）。
        let item: MDItem
    }

    private static func baseScore(name: String, path: String, query: String) -> Int {
        // 与热目录共用同一套档位（方案 A 归并排序）。MDQuery 的 [cd] 谓词已保证
        // 文件名实际命中；本地比较失败（变音符差异等）时兑底按“包含”档计。
        let tier = SearchRanking.nameTier(name: name, query: query) ?? SearchRanking.tierContains
        return tier - SearchRanking.depthPenalty(path: path)
    }

    private static func isExcluded(_ path: String) -> Bool {
        return SearchExclusionEngine.shared.isExcluded(path: path)
    }
}
