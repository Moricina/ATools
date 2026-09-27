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

        let queryId = UUID()
        currentQueryId = queryId
        runtimeLog("[Spotlight] searchFiles requested: '\(trimmed)', queryId=\(queryId)")

        // 1. Terminate the previous mdfind right away. The queue is serial and the previous
        // block may be parked in a blocking `availableData` read; killing the process hands it
        // EOF so the new query doesn't wait for the old one to finish on its own.
        terminateActiveProcess()

        queue.async { [weak self] in
            guard let self = self else { return }
            // A stale block may have spawned a process after the call above; clean it up too.
            self.terminateActiveProcess()
            guard self.currentQueryId == queryId else { return }

            var results: [SearchResult] = []
            var seenPaths = Set<String>()

            let home = FileManager.default.homeDirectoryForCurrentUser
            let lowerQuery = trimmed.lowercased()

            // 2. Hot folders (Downloads, Desktop, Documents) from an in-memory snapshot.
            // They used to be enumerated from disk for every debounced keystroke, on this same
            // serial queue, before mdfind could start. On TCC-protected or iCloud-synced
            // Desktop/Documents that alone took seconds per query.
            for file in self.hotFilesSnapshot(waitingUpTo: 0.3) {
                guard self.currentQueryId == queryId else { break }
                guard file.name.localizedCaseInsensitiveContains(trimmed), !seenPaths.contains(file.path) else { continue }
                seenPaths.insert(file.path)
                let path = file.path
                let score = file.name.lowercased().hasPrefix(lowerQuery) ? 70 : 60
                results.append(SearchResult(
                    title: file.name,
                    subtitle: path,
                    path: path,
                    type: file.isDirectory ? .folder : .file,
                    score: score,
                    action: {
                        LauncherExecutor.open(path: path)
                    }
                ))
                if results.count >= limit {
                    break
                }
            }

            guard self.currentQueryId == queryId else { return }

            // 3. System-wide Spotlight query via /usr/bin/mdfind
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")

            var env = ProcessInfo.processInfo.environment
            env["LANG"] = "zh_CN.UTF-8"
            env["LC_ALL"] = "zh_CN.UTF-8"
            process.environment = env
            process.currentDirectoryURL = home

            if trimmed.count == 1 {
                process.arguments = ["-onlyin", home.path, "-name", trimmed]
            } else {
                process.arguments = ["-name", trimmed]
            }

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            process.terminationHandler = { _ in }

            self.processLock.lock()
            self.activeProcess = process
            self.activePipe = pipe
            self.processLock.unlock()

            do {
                try process.run()
                runtimeLog("[Spotlight] mdfind process started (PID: \(process.processIdentifier)) for '\(trimmed)'")
            } catch {
                runtimeLog("[Spotlight] Failed to run mdfind: \(error)")
                self.terminateActiveProcess()
                DispatchQueue.main.async {
                    if self.currentQueryId == queryId {
                        completion(results)
                    }
                }
                return
            }

            let fileHandle = pipe.fileHandleForReading
            var buffer = Data()
            let delimiter = UInt8(ascii: "\n")
            var streamDone = false

            while !streamDone {
                guard self.currentQueryId == queryId else { break }
                let chunk = fileHandle.availableData
                if chunk.isEmpty {
                    break // EOF
                }
                buffer.append(chunk)

                while let newlineIndex = buffer.firstIndex(of: delimiter) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<newlineIndex)
                    buffer.removeSubrange(buffer.startIndex...newlineIndex)

                    guard let path = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
                        continue
                    }

                    if path.contains("/.Trash/") ||
                       path.contains("/DerivedData/") ||
                       path.contains("/node_modules/") ||
                       path.contains("/.git/") ||
                       path.contains("/Library/Caches/") ||
                       path.contains("/Library/Developer/CommandLineTools/") {
                        continue
                    }

                    if seenPaths.contains(path) { continue }
                    seenPaths.insert(path)

                    let url = URL(fileURLWithPath: path)
                    let name = url.lastPathComponent
                    if name.hasSuffix(".app") { continue }

                    let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    let score = name.lowercased().hasPrefix(lowerQuery) ? 55 : 45

                    results.append(SearchResult(
                        title: name,
                        subtitle: path,
                        path: path,
                        type: isDir ? .folder : .file,
                        score: score,
                        action: {
                            LauncherExecutor.open(path: path)
                        }
                    ))

                    if results.count >= limit {
                        streamDone = true
                        break
                    }
                }
            }

            self.terminateActiveProcess()

            guard self.currentQueryId == queryId else {
                runtimeLog("[Spotlight] Dropping results because currentQueryId changed")
                return
            }

            // Sort results by score descending, then by title length
            results.sort {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                return $0.title.count < $1.title.count
            }

            runtimeLog("[Spotlight] Total file search finished for '\(trimmed)', parsed results: \(results.count)")

            DispatchQueue.main.async {
                if self.currentQueryId == queryId {
                    completion(results)
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
        currentQueryId = UUID()
        terminateActiveProcess()
    }
}
