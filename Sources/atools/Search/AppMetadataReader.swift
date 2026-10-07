import Foundation

/// Reads application display metadata without creating cached NSBundle instances for every app.
public enum AppMetadataReader {
    public struct Metadata {
        public let bundleIdentifier: String?
        public let displayName: String?
        public let bundleName: String?
        public let localizedNames: [String]
        public let isUIElement: Bool
        public let isBackgroundOnly: Bool
    }

    public static func readBool(from plist: [String: Any]?, key: String) -> Bool {
        guard let val = plist?[key] else { return false }
        if let b = val as? Bool { return b }
        if let n = val as? NSNumber { return n.boolValue }
        if let s = val as? String { return s == "1" || s.lowercased() == "true" }
        return false
    }

    public static func read(appURL: URL) -> Metadata {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        let plist = (try? Data(contentsOf: infoURL)).flatMap {
            try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
        }

        var localized: [String] = []
        let resources = appURL.appendingPathComponent("Contents/Resources")
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: resources.path) {
            for entry in entries where entry.hasSuffix(".lproj") {
                let stringsURL = resources.appendingPathComponent(entry).appendingPathComponent("InfoPlist.strings")
                guard let strings = NSDictionary(contentsOf: stringsURL) else { continue }
                for key in ["CFBundleDisplayName", "CFBundleName"] {
                    if let value = strings[key] as? String, !value.isEmpty { localized.append(value) }
                }
            }
        }

        let displayName = plist?["CFBundleDisplayName"] as? String
        let bundleName = plist?["CFBundleName"] as? String
        let isUIElement = readBool(from: plist, key: "LSUIElement")
        let isBackgroundOnly = readBool(from: plist, key: "LSBackgroundOnly")

        return Metadata(
            bundleIdentifier: plist?["CFBundleIdentifier"] as? String,
            displayName: displayName,
            bundleName: bundleName,
            localizedNames: localized,
            isUIElement: isUIElement,
            isBackgroundOnly: isBackgroundOnly
        )
    }
}
