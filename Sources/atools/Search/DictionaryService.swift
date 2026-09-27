import Foundation
import CoreServices

public final class DictionaryService {
    public static let shared = DictionaryService()

    private let queue = DispatchQueue(label: "cc.atools.dictionary", qos: .userInitiated)
    private let cacheLock = NSLock()
    private var cache: [String: String] = [:]
    /// Generation token incremented on every new lookup request. Late callbacks
    /// from a previous generation are discarded so stale results never overwrite
    /// a more recent search.
    private var currentGeneration: UInt64 = 0

    private init() {}

    public func lookup(_ word: String) -> String? {
        let key = normalizedKey(word)
        cacheLock.lock()
        if let cached = cache[key] {
            cacheLock.unlock()
            return cached.isEmpty ? nil : cached
        }
        cacheLock.unlock()
        let value = lookupNow(word) ?? ""
        cacheLock.lock()
        cache[key] = value
        cacheLock.unlock()
        return value.isEmpty ? nil : value
    }

    /// Dictionary services can be slow on their first call, so search never runs this on main.
    /// The generation token ensures late results from a previous query are silently dropped.
    public func lookup(_ word: String, generation: UInt64 = 0, completion: @escaping (String?) -> Void) {
        queue.async { [weak self] in
            guard let self = self else { return }
            let result = self.lookup(word)
            // If a generation was provided, check it is still current.
            if generation > 0 {
                self.cacheLock.lock()
                let isCurrent = self.currentGeneration == generation
                self.cacheLock.unlock()
                guard isCurrent else { return }
            }
            completion(result)
        }
    }

    /// Bumps the generation counter so all pending lookups from earlier searches are discarded.
    public func cancelPendingLookups() {
        cacheLock.lock()
        currentGeneration &+= 1
        let gen = currentGeneration
        cacheLock.unlock()
        // Return current generation so caller can pass it to lookup().
        _ = gen
    }

    private func normalizedKey(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func lookupNow(_ word: String) -> String? {
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
