import Foundation
import CoreServices
import UniformTypeIdentifiers

/// Full-disk file search backed by CoreServices `MDQuery`.
///
/// `MDQuery` executes on a background serial queue, declares the attributes it will read
/// up-front so they arrive batched with the results, supports active cancellation via
/// `MDQueryStop`, and outputs `Sendable` `RawSearchResultPayload` values across isolation boundaries.
public final class MetadataFileSearchBackend: NSObject {
    public static let shared = MetadataFileSearchBackend()

    /// 查询范围。`.directories` 用于单字符查询：命中量仍可控，但完整覆盖目录全深度
    /// （热目录快照只到 3 层，MDQuery 范围内到任意深度）。
    public enum ScopeTarget: Sendable {
        case computer
        case directories([URL])
    }

    /// Serial queue: at most one MDQuery runs at a time.
    private let queue = DispatchQueue(label: "cc.atools.metadata.mdquery", qos: .userInitiated)
    private let idLock = NSLock()
    private var currentSearchID = UUID()
    private var activeMDQuery: MDQuery?

    /// Prefetched alongside every result.
    private static let prefetchAttributes: [CFString] = [
        kMDItemPath!
    ]

    /// Q-12: 大小写无关判断是否为应用包或系统偏好设置面板
    @inline(__always)
    public static func isApplicationOrPrefPane(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension
        guard !ext.isEmpty else { return false }
        return ext.caseInsensitiveCompare("app") == .orderedSame
            || ext.caseInsensitiveCompare("prefPane") == .orderedSame
    }

    /// 构建 Spotlight 查询谓词。
    static func predicateText(matching text: String, filter: SearchTypeFilter = .all) -> String {
        let clean = SearchInputSanitizer.sanitize(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "" }

        var escaped = ""
        escaped.reserveCapacity(clean.count * 2)
        for ch in clean {
            switch ch {
            case "\\": escaped += "\\\\"   // 反斜杠先转
            case "'":  escaped += "\\'"
            case "*":  escaped += "\\*"    // 防止用户输入变成通配符（如 a*b 扫全盘）
            case "?":  escaped += "\\?"
            case "\"": escaped += "\\\""
            default:   escaped.append(ch)
            }
        }
        let basePred = "(kMDItemFSName == '*\(escaped)*'cd || kMDItemDisplayName == '*\(escaped)*'cd)"
        if let typePred = filter.mdQueryContentTypePredicate {
            return "(\(basePred) && \(typePred))"
        }
        return basePred
    }

    /// 军师加固点 2：后台产出纯值类型 Sendable 的 RawSearchResultPayload
    public func searchPayloads(
        matching text: String,
        limit: Int,
        scope: ScopeTarget = .computer,
        filter: SearchTypeFilter = .all,
        completion: @escaping @Sendable ([RawSearchResultPayload]) -> Void
    ) {
        let searchID = UUID()
        idLock.lock()
        currentSearchID = searchID
        if let runningQuery = activeMDQuery {
            MDQueryStop(runningQuery)
        }
        idLock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            guard self.isCurrent(searchID) else { return }

            let payloads = self.executePayloads(
                searchID: searchID,
                predicateText: text,
                limit: limit,
                scope: scope,
                filter: filter
            )

            guard self.isCurrent(searchID) else { return }
            completion(payloads)
        }
    }

    public func search(
        matching text: String,
        limit: Int,
        scope: ScopeTarget = .computer,
        filter: SearchTypeFilter = .all,
        completion: @escaping ([SearchResult]) -> Void
    ) {
        searchPayloads(matching: text, limit: limit, scope: scope, filter: filter) { payloads in
            let results = payloads.map { $0.materializeSearchResult() }
            completion(results)
        }
    }

    /// Q-04: 取消时不仅轮换 currentSearchID，还主动调用 MDQueryStop 中断正在执行的底层内核查询
    public func cancel() {
        idLock.lock()
        currentSearchID = UUID()
        let queryToStop = activeMDQuery
        idLock.unlock()
        if let q = queryToStop {
            MDQueryStop(q)
        }
    }

    private func isCurrent(_ id: UUID) -> Bool {
        idLock.lock()
        defer { idLock.unlock() }
        return currentSearchID == id
    }

    private func executePayloads(
        searchID: UUID,
        predicateText text: String,
        limit: Int,
        scope: ScopeTarget,
        filter: SearchTypeFilter = .all
    ) -> [RawSearchResultPayload] {
        let predicate = Self.predicateText(matching: text, filter: filter)
        guard !predicate.isEmpty else { return [] }

        guard let query = MDQueryCreate(kCFAllocatorDefault, predicate as CFString,
                                        Self.prefetchAttributes as CFArray, [] as CFArray) else {
            runtimeLog("[MDQuery] predicate not parsable: \(predicate)")
            return []
        }

        switch scope {
        case .computer:
            MDQuerySetSearchScope(query, [kMDQueryScopeComputer!] as CFArray, 0)
        case .directories(let urls):
            MDQuerySetSearchScope(query, urls.map { $0 as CFURL } as CFArray, 0)
        }

        idLock.lock()
        guard currentSearchID == searchID else {
            idLock.unlock()
            return []
        }
        activeMDQuery = query
        idLock.unlock()

        defer {
            idLock.lock()
            if activeMDQuery === query {
                activeMDQuery = nil
            }
            idLock.unlock()
        }

        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else {
            runtimeLog("[MDQuery] execute failed: \(predicate)")
            return []
        }

        guard isCurrent(searchID) else {
            MDQueryStop(query)
            return []
        }

        // Q-03: 严格边界钳制与防整数溢出容量预分配
        let safeLimit = max(AppConstants.searchResultLimitRange.lowerBound, min(AppConstants.searchResultLimitRange.upperBound, limit))
        let count = max(0, MDQueryGetResultCount(query))
        let mult = safeLimit.multipliedReportingOverflow(by: 8)
        let capBound = mult.overflow ? 1600 : max(0, mult.partialValue)

        var candidates: [Candidate] = []
        candidates.reserveCapacity(min(Int(count), capBound))

        var localizedResolutionsCount = 0
        let maxLocalizedResolutions = 64 // XPC 熔断上限

        for index in 0..<count {
            if (index & 63) == 0 && !isCurrent(searchID) {
                MDQueryStop(query)
                return []
            }
            guard let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()

            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String,
                  !path.isEmpty,
                  !Self.isExcluded(path) else { continue }

            let isApp = Self.isApplicationOrPrefPane(path)
            if filter == .application && !isApp { continue }
            if filter != .application && filter != .all && isApp { continue }

            let rawName = (path as NSString).lastPathComponent
            var resolvedName = rawName

            let cleanDiskName = rawName.hasSuffix(".localized")
                ? String(rawName.dropLast(".localized".count))
                : rawName

            var tier = SearchRanking.nameTier(name: cleanDiskName, query: text)

            if tier == nil && localizedResolutionsCount < maxLocalizedResolutions {
                localizedResolutionsCount += 1
                let dn = (MDItemCopyAttribute(item, kMDItemDisplayName) as? String)
                    ?? FileManager.default.displayName(atPath: path)
                if !dn.isEmpty {
                    resolvedName = dn
                    tier = SearchRanking.nameTier(name: dn, query: text)
                }
            } else if rawName.hasSuffix(".localized") {
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
                name: resolvedName,
                path: path,
                item: item
            ))
        }

        // Q-08: 扩大第二轮粗排候选池（至少 max(safeLimit * 3, 100)），在全量计算新鲜度加分后再做最终截断，
        // 防止刚修改的高新鲜度文件在第一阶段因基础分微弱劣势被提前截断丢弃。
        let coarsePoolSize = min(candidates.count, max(safeLimit * 3, 100))
        let topPool = candidates.sorted { $0.baseScore > $1.baseScore }.prefix(coarsePoolSize)
        var finalized: [(score: Int, name: String, path: String, isFolder: Bool)] = []
        finalized.reserveCapacity(topPool.count)

        for c in topPool {
            if !isCurrent(searchID) {
                MDQueryStop(query)
                return []
            }
            let modified = MDItemCopyAttribute(c.item, kMDItemContentModificationDate) as? Date
            let lastUsed = MDItemCopyAttribute(c.item, kMDItemLastUsedDate) as? Date
            let contentType = MDItemCopyAttribute(c.item, kMDItemContentType) as? String
            let isApp = Self.isApplicationOrPrefPane(c.path)
            let isFolder = !isApp && (contentType.map { UTType($0)?.conforms(to: .folder) ?? false } ?? false)

            let score = c.baseScore + SearchRanking.freshnessScore(modified: modified, lastUsed: lastUsed)
            finalized.append((score, c.name, c.path, isFolder))
        }

        let best = finalized.sorted { $0.score > $1.score }.prefix(safeLimit)
        return best.map { c in
            let path = c.path
            let isApp = Self.isApplicationOrPrefPane(path)
            let type: SearchResultType = isApp ? .application : (c.isFolder ? .folder : .file)
            let name = isApp ? (c.name as NSString).deletingPathExtension : c.name
            return RawSearchResultPayload(
                title: name,
                subtitle: path,
                path: path,
                type: type,
                score: c.score
            )
        }
    }

    private struct Candidate {
        let baseScore: Int
        let name: String
        let path: String
        /// Top-N 复审阶段读属性用；ARC 持有到 executePayloads() 结束（先于 query 释放）。
        let item: MDItem
    }

    private static func isExcluded(_ path: String) -> Bool {
        return SearchExclusionEngine.shared.isExcluded(path: path)
    }
}
