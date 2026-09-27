import Foundation

/// Diagnostic log. Disabled by default: it used to open/append/close /tmp/atools_runtime.log
/// synchronously on the main thread for every keystroke, grew without bound and exposed
/// search queries and file names in a world-readable location.
/// Enable with `defaults write cc.atools.app atools.debugLog -bool YES` or `ATOOLS_DEBUG_LOG=1`.
private enum RuntimeLogSink {
    static let isEnabled: Bool = {
        ProcessInfo.processInfo.environment["ATOOLS_DEBUG_LOG"] == "1"
            || UserDefaults.standard.bool(forKey: "atools.debugLog")
            || CommandLine.arguments.contains("--test")
    }()

    static let queue = DispatchQueue(label: "cc.atools.runtime-log", qos: .utility)
    static let maxBytes: UInt64 = 2 * 1024 * 1024

    static let url: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/ATools", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("runtime.log")
    }()

    static var handle: FileHandle? = {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        return try? FileHandle(forWritingTo: url)
    }()

    static func write(_ data: Data) {
        guard let handle = handle else { return }
        do {
            let size = try handle.seekToEnd()
            if size > maxBytes {
                try handle.truncate(atOffset: 0)
            }
            try handle.write(contentsOf: data)
        } catch {
            // Logging must never crash the app (the old FileHandle APIs raised ObjC exceptions).
        }
    }
}

public func runtimeLog(_ message: @autoclosure () -> String) {
    guard RuntimeLogSink.isEnabled else { return }
    let line = "[\(Date())] \(message())\n"
    guard let data = line.data(using: .utf8) else { return }
    RuntimeLogSink.queue.async {
        RuntimeLogSink.write(data)
    }
}
