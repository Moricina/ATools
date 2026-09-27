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

    /// Prefetched alongside every result, so scoring never pays an XPC per item.
    private static let prefetchAttributes: [CFString] = [
        kMDItemFSName!,
        kMDItemPath!,
        kMDItemContentType!,
        kMDItemContentModificationDate!,
        kMDItemLastUsedDate!
    ]

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
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        // CONTAINS[cd] is literal (no LIKE wildcards) and case/diacritic insensitive.
        let predicate = "kMDItemFSName CONTAINS[cd] '\(escaped)'"

        guard let query = MDQueryCreate(
            kCFAllocatorDefault,
            predicate as CFString,
            Self.prefetchAttributes as CFArray,
            [] as CFArray
        ) else { return [] }

        MDQuerySetSearchScope(query, [kMDQueryScopeComputer!] as CFArray, 0)
        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)) else { return [] }

        let count = MDQueryGetResultCount(query)
        // Lightweight candidates first: only the top `limit` become SearchResult
        // objects (closures + string copies), so a huge match set never turns
        // into a huge allocation storm.
        var candidates: [Candidate] = []
        candidates.reserveCapacity(min(Int(count), limit * 8))

        for index in 0..<count {
            guard let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = Unmanaged<MDItem>.fromOpaque(raw).takeUnretainedValue()

            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String,
                  !path.isEmpty,
                  !path.hasSuffix(".app"),
                  !Self.isExcluded(path) else { continue }

            let name = (MDItemCopyAttribute(item, kMDItemFSName) as? String)
                ?? (path as NSString).lastPathComponent
            let modified = MDItemCopyAttribute(item, kMDItemContentModificationDate) as? Date
            let lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
            let contentType = MDItemCopyAttribute(item, kMDItemContentType) as? String
            let isFolder = contentType.map { UTType($0)?.conforms(to: .folder) ?? false } ?? false

            let score = Self.score(name: name, path: path, query: lower,
                                   modified: modified, lastUsed: lastUsed)
            candidates.append(Candidate(score: score, name: name, path: path,
                                        isFolder: isFolder, modified: modified))
        }

        let top = candidates.sorted { $0.score > $1.score }.prefix(max(1, limit))
        return top.map { c in
            let path = c.path
            return SearchResult(title: c.name, subtitle: path, path: path,
                                type: c.isFolder ? .folder : .file,
                                score: c.score,
                                action: { LauncherExecutor.open(path: path) })
        }
    }

    private struct Candidate {
        let score: Int
        let name: String
        let path: String
        let isFolder: Bool
        let modified: Date?
    }

    private static func score(name: String, path: String, query: String, modified: Date?, lastUsed: Date?) -> Int {
        let lower = name.lowercased()
        var score = lower == query ? 120 : (lower.hasPrefix(query) ? 105 : (lower.contains(query) ? 90 : 60))
        if let lastUsed { score += min(12, max(0, 12 - Int(Date().timeIntervalSince(lastUsed) / 86_400))) }
        if let modified { score += min(8, max(0, 8 - Int(Date().timeIntervalSince(modified) / 86_400))) }
        // NSString pathComponents avoids allocating an NSURL per item.
        score -= min(10, (path as NSString).pathComponents.count)
        return score
    }

    private static func isExcluded(_ path: String) -> Bool {
        let excluded = ["/.Trash/", "/DerivedData/", "/node_modules/", "/.git/", "/Library/Caches/", "/Library/Developer/CommandLineTools/"]
        return excluded.contains(where: path.contains)
    }
}
