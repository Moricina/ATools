import Foundation

public func runtimeLog(_ message: String) {
    let line = "[\(Date())] \(message)\n"
    if let data = line.data(using: .utf8) {
        if let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/atools_runtime.log")) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: URL(fileURLWithPath: "/tmp/atools_runtime.log"))
        }
    }
}
