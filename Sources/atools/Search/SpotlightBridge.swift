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
                guard file.name.localizedCaseInsensitiveContains(trimmed) else { return nil }
                let path = file.path
                return SearchResult(title: file.name, subtitle: path, path: path,
                                    type: file.isDirectory ? .folder : .file,
                                    score: file.name.lowercased().hasPrefix(trimmed.lowercased()) ? 125 : 115,
                                    action: { LauncherExecutor.open(path: path) })
            }

            // One ASCII character matches an enormous fraction of the disk (empirically
            // tens of seconds of scanning), so the hot folders + app index cover those
            // keystrokes and full metadata starts at two characters.
            //
            // CJK 是例外：单个汉字/假名/谚文本身就是完整检索词（如 "报"），
            // 实测全盘命中量与耗时都很小（~100-300ms），中文用户习惯单字起搜，
            // 放行到全盘不会重踏性能坑。
            let firstChar = trimmed.first
            let singleCharFullDiskOK = trimmed.count >= 2 || (firstChar.map { Self.isCJK($0) } ?? false)
            guard singleCharFullDiskOK else {
                DispatchQueue.main.async {
                    completion(Array(hot.prefix(limit)))
                }
                return
            }

            MetadataFileSearchBackend.shared.search(matching: trimmed, limit: limit) { metadataResults in
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

    private struct HotFile {
        let name: String
        let path: String
        let isDirectory: Bool
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
            for folder in ["Downloads", "Desktop", "Documents"] {
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
            files.append(HotFile(name: filename, path: fileURL.path, isDirectory: isDir))
        }
        return files
    }

    /// Returns the current snapshot, briefly waiting for an in-progress rebuild.
    private func hotFilesSnapshot(waitingUpTo timeout: TimeInterval) -> [HotFile] {
        warmHotFolderCache()
        let deadline = Date().addingTimeInterval(timeout)
        hotCacheCondition.lock()
        defer { hotCacheCondition.unlock() }
        // Wait for the rebuild's Downloads listing (usually milliseconds) so just-downloaded
        // files show up; slower folders are used from the previous snapshot meanwhile.
        while isBuildingHotCache,
              (hotFolderUpdated["Downloads"] ?? .distantPast) < hotCacheBuildStarted,
              hotCacheCondition.wait(until: deadline) {}
        return ["Downloads", "Desktop", "Documents"].flatMap { hotCache[$0] ?? [] }
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
    }
}
