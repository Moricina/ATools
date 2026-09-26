import Foundation
import AppKit

public struct IndexedApp {
    public let name: String
    public let localizedName: String
    public let path: String
    public let bundleId: String?
    public let aliases: [String]
    public let pinyins: [String]
    public let pinyinAbbrs: [String]

    public init(name: String, localizedName: String, path: String, bundleId: String?, additionalAliases: [String] = []) {
        self.name = name
        self.localizedName = localizedName
        self.path = path
        self.bundleId = bundleId

        var allAliases = Set<String>()
        allAliases.insert(name)
        allAliases.insert(localizedName)
        for a in additionalAliases where !a.isEmpty {
            allAliases.insert(a)
        }
        self.aliases = Array(allAliases)

        var pinyinList: [String] = []
        var abbrList: [String] = []

        for alias in self.aliases {
            let (full, abbr) = IndexedApp.pinyinAndAbbr(alias)
            if !full.isEmpty {
                pinyinList.append(full)
            }
            if !abbr.isEmpty {
                abbrList.append(abbr)
            }
        }

        self.pinyins = pinyinList
        self.pinyinAbbrs = abbrList
    }

    private static func pinyinAndAbbr(_ text: String) -> (full: String, abbr: String) {
        let mutableString = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutableString, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
        let spaced = mutableString as String
        let words = spaced.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        var abbr = ""
        for w in words where !w.isEmpty {
            if let first = w.first {
                abbr.append(first)
            }
        }
        let full = spaced.replacingOccurrences(of: " ", with: "")
        return (full.lowercased(), abbr.lowercased())
    }
}

public final class AppHotspotIndex {
    public static let shared = AppHotspotIndex()

    private var apps: [IndexedApp] = []
    private let appsLock = NSLock()
    private let queue = DispatchQueue(label: "cc.atools.appindex", qos: .userInitiated)
    private var isIndexing = false

    private init() {
        refreshIndex()
    }

    public func refreshIndex(completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self = self else { return }
            var results: [IndexedApp] = []
            var visitedPaths = Set<String>()

            let directoriesToScan = self.collectAppDirectories()

            for dir in directoriesToScan {
                guard FileManager.default.fileExists(atPath: dir) else { continue }
                self.scanDirectoryFast(dir, depth: 0, maxDepth: AppConstants.appIndexScanDepth, results: &results, visitedPaths: &visitedPaths)
            }

            self.appsLock.lock()
            self.apps = results
            self.appsLock.unlock()
            self.isIndexing = false
            completion?()
        }
    }

    private func collectAppDirectories() -> [String] {
        let home = NSHomeDirectory()
        return [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices/Applications",
            "/System/Library/CoreServices",
            "/System/Cryptexes/App/System/Applications",
            "\(home)/Applications",
            "/Applications/Setapp",
            "/opt/homebrew/Caskroom",
            "/usr/local/Caskroom",
            "\(home)/Library/Application Support/Steam/steamapps/common",
            "/System/Library/PreferencePanes",
            "/Library/PreferencePanes",
            "\(home)/Library/PreferencePanes"
        ]
    }

    private func scanDirectoryFast(_ dir: String, depth: Int, maxDepth: Int, results: inout [IndexedApp], visitedPaths: inout Set<String>) {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }

        for item in contents {
            if item.hasPrefix(".") { continue }
            let fullPath = (dir as NSString).appendingPathComponent(item)

            if item.hasSuffix(".app") || item.hasSuffix(".prefPane") {
                if !visitedPaths.contains(fullPath) {
                    visitedPaths.insert(fullPath)
                    autoreleasepool {
                        let baseName = (item as NSString).deletingPathExtension
                        var aliases: [String] = []

                        // 1. LaunchServices localized name via URL resource values
                        let fileURL = URL(fileURLWithPath: fullPath)
                        let resourceValues = try? fileURL.resourceValues(forKeys: [.localizedNameKey])
                        let lsName = resourceValues?.localizedName?.replacingOccurrences(of: ".app", with: "")

                        if let ls = lsName, !ls.isEmpty && ls != baseName {
                            aliases.append(ls)
                        }

                        // 2. Deep bundle localized strings (zh-Hans, zh_CN, zh-Hant)
                        if let bundle = Bundle(path: fullPath) {
                            for loc in ["zh-Hans", "zh_CN", "zh-Hant"] {
                                if let zhPath = bundle.path(forResource: "InfoPlist", ofType: "strings", inDirectory: nil, forLocalization: loc),
                                   let dict = NSDictionary(contentsOfFile: zhPath) {
                                    if let disp = dict["CFBundleDisplayName"] as? String, !disp.isEmpty {
                                        aliases.append(disp)
                                    }
                                    if let bName = dict["CFBundleName"] as? String, !bName.isEmpty {
                                        aliases.append(bName)
                                    }
                                }
                            }
                            if let disp = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !disp.isEmpty {
                                aliases.append(disp)
                            }
                            if let bName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, !bName.isEmpty {
                                aliases.append(bName)
                            }
                        }

                        // 3. Fallback well-known Chinese mappings for standard apps
                        if let wellKnown = AppHotspotIndex.wellKnownAliases[baseName] {
                            aliases.append(contentsOf: wellKnown)
                        }

                        let primaryLocalizedName = aliases.first ?? lsName ?? baseName
                        let indexed = IndexedApp(
                            name: baseName,
                            localizedName: primaryLocalizedName,
                            path: fullPath,
                            bundleId: nil,
                            additionalAliases: aliases
                        )
                        results.append(indexed)
                    }
                }
            } else if depth < maxDepth {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
                    if !item.hasSuffix(".app") && !item.hasSuffix(".framework") && !item.hasSuffix(".lproj") {
                        scanDirectoryFast(fullPath, depth: depth + 1, maxDepth: maxDepth, results: &results, visitedPaths: &visitedPaths)
                    }
                }
            }
        }
    }

    private static let wellKnownAliases: [String: [String]] = [
        "WeChat": ["微信"],
        "Finder": ["访达"],
        "Terminal": ["终端"],
        "Notes": ["备忘录"],
        "System Settings": ["系统设置", "设置"],
        "System Preferences": ["系统偏好设置", "偏好设置"],
        "Safari": ["Safari 浏览器", "浏览器"],
        "Music": ["音乐"],
        "Maps": ["地图"],
        "Calculator": ["计算器"],
        "Calendar": ["日历"],
        "Mail": ["邮件"],
        "Reminders": ["提醒事项"],
        "Photos": ["照片"],
        "TextEdit": ["文本编辑"],
        "Activity Monitor": ["活动监视器"],
        "Keychain Access": ["钥匙串访问", "钥匙串"],
        "Console": ["控制台"],
        "Disk Utility": ["磁盘工具"],
        "BaiduNetdisk": ["百度网盘", "网盘"],
        "Feishu": ["飞书"],
        "DingTalk": ["钉钉"],
        "WXWork": ["企业微信", "企微"],
        "TencentMeeting": ["腾讯会议"],
        "QQ": ["腾讯QQ", "QQ音乐"],
        "NeteaseMusic": ["网易云音乐"]
    ]

    public func search(_ query: String) -> [IndexedApp] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        let snapshot: [IndexedApp]
        appsLock.lock()
        snapshot = self.apps
        appsLock.unlock()

        var exactMatches: [IndexedApp] = []
        var prefixMatches: [IndexedApp] = []
        var pinyinMatches: [IndexedApp] = []
        var fuzzyMatches: [IndexedApp] = []

        for app in snapshot {
            var matchedExact = false
            var matchedPrefix = false
            var matchedPinyin = false
            var matchedFuzzy = false

            for alias in app.aliases {
                let lower = alias.lowercased()
                if lower == q {
                    matchedExact = true
                    break
                } else if lower.hasPrefix(q) {
                    matchedPrefix = true
                } else if lower.contains(q) {
                    matchedFuzzy = true
                }
            }

            if matchedExact {
                exactMatches.append(app)
                continue
            }

            for py in app.pinyins {
                if py == q || py.hasPrefix(q) {
                    matchedPinyin = true
                    break
                }
            }

            if !matchedPinyin {
                for abbr in app.pinyinAbbrs {
                    if abbr == q || abbr.hasPrefix(q) {
                        matchedPinyin = true
                        break
                    }
                }
            }

            if matchedPrefix {
                prefixMatches.append(app)
            } else if matchedPinyin {
                pinyinMatches.append(app)
            } else if matchedFuzzy {
                fuzzyMatches.append(app)
            }
        }

        return exactMatches + prefixMatches + pinyinMatches + fuzzyMatches
    }
}
