import Foundation
import CoreServices
import AppKit

public final class SpotlightBridge {
    public static let shared = SpotlightBridge()

    private let processLock = NSLock()
    private var activeProcess: Process?
    private var activePipe: Pipe?
    private let queue = DispatchQueue(label: "cc.atools.spotlight.process", qos: .userInitiated)
    private var currentQueryId = UUID()

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

        queue.async { [weak self] in
            guard let self = self else { return }

            // 1. Terminate any previous active process immediately
            self.terminateActiveProcess()

            guard self.currentQueryId == queryId else { return }

            var results: [SearchResult] = []
            var seenPaths = Set<String>()
            let lock = NSLock()

            let home = FileManager.default.homeDirectoryForCurrentUser
            let lowerQuery = trimmed.lowercased()

            // 2. Fast scan of user primary hot folders (Downloads, Desktop, Documents)
            // Guarantees instant results for active working files regardless of Spotlight indexing state
            let hotFolders = [
                home.appendingPathComponent("Downloads"),
                home.appendingPathComponent("Desktop"),
                home.appendingPathComponent("Documents")
            ]

            for folder in hotFolders {
                guard self.currentQueryId == queryId else { break }
                guard let enumerator = FileManager.default.enumerator(
                    at: folder,
                    includingPropertiesForKeys: [.nameKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }

                for case let fileURL as URL in enumerator {
                    guard self.currentQueryId == queryId else { break }
                    if enumerator.level > AppConstants.spotlightHotFolderDepth {
                        enumerator.skipDescendants()
                        continue
                    }

                    let filename = fileURL.lastPathComponent
                    if filename.hasPrefix(".") || filename.hasSuffix(".app") { continue }

                    if filename == "node_modules" || filename == "DerivedData" || filename == ".git" {
                        enumerator.skipDescendants()
                        continue
                    }

                    if filename.localizedCaseInsensitiveContains(trimmed) {
                        let path = fileURL.path
                        lock.lock()
                        if !seenPaths.contains(path) {
                            seenPaths.insert(path)
                            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                            let score = filename.lowercased().hasPrefix(lowerQuery) ? 70 : 60
                            results.append(SearchResult(
                                title: filename,
                                subtitle: path,
                                path: path,
                                type: isDir ? .folder : .file,
                                score: score,
                                action: {
                                    LauncherExecutor.open(path: path)
                                }
                            ))
                        }
                        lock.unlock()
                    }

                    if seenPaths.count >= limit {
                        break
                    }
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

                    lock.lock()
                    let alreadySeen = seenPaths.contains(path)
                    if !alreadySeen {
                        seenPaths.insert(path)
                    }
                    lock.unlock()

                    if alreadySeen { continue }

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

    public func stop() {
        currentQueryId = UUID()
        terminateActiveProcess()
    }
}
