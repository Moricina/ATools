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
    static func predicateText(matching text: String) -> String {
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
        return "kMDItemFSName == '*\(escaped)*'cd"
    }

    public func search(matching text: String, limit: Int, completion: @escaping ([SearchResult]) -> Void) {
        let searchID = UUID()
        idLock.lock()
        currentSearchID = searchID
        idLock.unlock()

        queue.async { [weak self] in
            guard let self else { return }
            // Coalesce: a newer request arrived while this one was queued.
            guard self.isCurrent(searchID) else { return }

            let results = self.execute(predicateText: text, limit: limit)

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

    private func execute(predicateText text: String, limit: Int) -> [SearchResult] {
        let lower = text.lowercased()
        let predicate = Self.predicateText(matching: text)

        guard let query = MDQueryCreate(kCFAllocatorDefault, predicate as CFString,
                                        Self.prefetchAttributes as CFArray, [] as CFArray) else {
            runtimeLog("[MDQuery] predicate not parsable: \(predicate)")
            return []
        }

        MDQuerySetSearchScope(query, [kMDQueryScopeComputer!] as CFArray, 0)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else {
            runtimeLog("[MDQuery] execute failed: \(predicate)")
            return []
        }

        let count = MDQueryGetResultCount(query)
        // 第一轮（全量）：只读 kMDItemPath —— 免费；其余属性每条 0.28ms XPC。
        // 旧实现在这一轮就读 5 个属性，扫 6801 条要 8 秒；同样数据现在 ~70ms。
        var candidates: [Candidate] = []
        candidates.reserveCapacity(min(Int(count), limit * 8))

        for index in 0..<count {
            guard let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()

            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String,
                  !path.isEmpty,
                  !path.hasSuffix(".app"),
                  !Self.isExcluded(path) else { continue }

            let name = (path as NSString).lastPathComponent
            candidates.append(Candidate(
                baseScore: Self.baseScore(name: name, path: path, query: lower),
                name: name, path: path, item: item))
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

            var score = c.baseScore
            if let lastUsed { score += min(12, max(0, 12 - Int(Date().timeIntervalSince(lastUsed) / 86_400))) }
            if let modified { score += min(8, max(0, 8 - Int(Date().timeIntervalSince(modified) / 86_400))) }
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
        let lower = name.lowercased()
        var score = lower == query ? 120 : (lower.hasPrefix(query) ? 105 : (lower.contains(query) ? 90 : 60))
        // NSString pathComponents avoids allocating an NSURL per item.
        score -= min(10, (path as NSString).pathComponents.count)
        return score
    }

    private static func isExcluded(_ path: String) -> Bool {
        let excluded = ["/.Trash/", "/DerivedData/", "/node_modules/", "/.git/", "/Library/Caches/", "/Library/Developer/CommandLineTools/"]
        return excluded.contains(where: path.contains)
    }
}
