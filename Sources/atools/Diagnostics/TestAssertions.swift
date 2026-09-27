import Foundation

/// Diagnostic assertions that remain active in release builds. The old `assert` calls were
/// compiled out by `swift build -c release`, allowing broken release builds to pass silently.
public enum TestAssertions {
    public static var failures: Int { sharedFailureCount }
    private static var sharedFailureCount = 0

    @discardableResult
    public static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> Bool {
        guard !condition() else { return true }
        sharedFailureCount += 1
        let detail = message()
        let location = "\(file):\(line)"
        FileHandle.standardError.write(Data("[FAIL] \(location) \(detail)\n".utf8))
        return false
    }
}
