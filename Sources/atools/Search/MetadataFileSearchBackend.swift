import Foundation

public final class MetadataFileSearchBackend: NSObject {
    public static let shared = MetadataFileSearchBackend()

    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?
    private var completion: (([SearchResult]) -> Void)?

    public func search(matching text: String, limit: Int, completion: @escaping ([SearchResult]) -> Void) {
        cancel()
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.predicate = NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, text)
        query.notificationBatchingInterval = 0.05
        self.query = query
        self.completion = completion

        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
        ) { [weak self, weak query] _ in
            guard let self, let query else { return }
            let results = self.results(from: query, matching: text, limit: limit)
            self.finish(results)
        }
        query.start()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self, weak query] in
            guard let self, let query, self.query === query else { return }
            self.finish(self.results(from: query, matching: text, limit: limit))
        }
    }

    public func cancel() {
        query?.stop()
        query = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        completion = nil
    }

    private func finish(_ results: [SearchResult]) {
        let completion = self.completion
        cancel()
        completion?(results)
    }

    private func results(from query: NSMetadataQuery, matching text: String, limit: Int) -> [SearchResult] {
        let lower = text.lowercased()
        var results: [SearchResult] = []
        for case let item as NSMetadataItem in query.results {
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !Self.isExcluded(path),
                  !path.hasSuffix(".app") else { continue }
            let url = URL(fileURLWithPath: path)
            let name = (item.value(forAttribute: NSMetadataItemFSNameKey) as? String) ?? url.lastPathComponent
            let modified = item.value(forAttribute: NSMetadataItemContentModificationDateKey) as? Date
            let lastUsed = item.value(forAttribute: NSMetadataItemLastUsedDateKey) as? Date
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let score = Self.score(name: name, path: path, query: lower, modified: modified, lastUsed: lastUsed)
            results.append(SearchResult(title: name, subtitle: path, path: path,
                                        type: isDirectory ? .folder : .file, score: score,
                                        action: { LauncherExecutor.open(path: path) }))
        }
        return Array(results.sorted { $0.score > $1.score }.prefix(max(1, limit)))
    }

    private static func score(name: String, path: String, query: String, modified: Date?, lastUsed: Date?) -> Int {
        let lower = name.lowercased()
        var score = lower == query ? 120 : (lower.hasPrefix(query) ? 105 : (lower.contains(query) ? 90 : 60))
        if let lastUsed { score += min(12, max(0, 12 - Int(Date().timeIntervalSince(lastUsed) / 86_400))) }
        if let modified { score += min(8, max(0, 8 - Int(Date().timeIntervalSince(modified) / 86_400))) }
        score -= min(10, URL(fileURLWithPath: path).pathComponents.count)
        return score
    }

    private static func isExcluded(_ path: String) -> Bool {
        let excluded = ["/.Trash/", "/DerivedData/", "/node_modules/", "/.git/", "/Library/Caches/", "/Library/Developer/CommandLineTools/"]
        return excluded.contains(where: path.contains)
    }
}
