import Foundation
import CoreServices

public final class DictionaryService {
    public static let shared = DictionaryService()

    private init() {}

    public func lookup(_ word: String) -> String? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 && trimmed.count <= 40 else { return nil }

        let nsString = trimmed as NSString
        let range = CFRangeMake(0, nsString.length)

        guard let definition = DCSCopyTextDefinition(nil, nsString as CFString, range) else {
            return nil
        }

        let defString = (definition.takeRetainedValue() as String)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        
        guard !defString.isEmpty else { return nil }

        // Truncate to reasonable preview length
        if defString.count > 120 {
            return String(defString.prefix(120)) + "..."
        }
        return defString
    }
}
