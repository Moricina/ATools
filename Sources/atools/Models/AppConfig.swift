import Foundation
import AppKit

public enum HotkeySpecialTrigger: String, Codable {
    case none
    case doubleCommand
    case doubleOption
    case doubleControl
    case doubleShift

    public var displayPrefix: String {
        switch self {
        case .none: return ""
        case .doubleCommand: return "2× ⌘ Command"
        case .doubleOption: return "2× ⌥ Option"
        case .doubleControl: return "2× ⌃ Control"
        case .doubleShift: return "2× ⇧ Shift"
        }
    }
}

public struct HotkeyBinding: Codable, Equatable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32
    public var displayString: String
    public var specialTrigger: HotkeySpecialTrigger

    public init(
        keyCode: UInt32,
        carbonModifiers: UInt32,
        displayString: String,
        specialTrigger: HotkeySpecialTrigger = .none
    ) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.displayString = displayString
        self.specialTrigger = specialTrigger
    }

    enum CodingKeys: String, CodingKey {
        case keyCode, carbonModifiers, displayString, specialTrigger
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.keyCode = (try? container.decode(UInt32.self, forKey: .keyCode)) ?? 0
        self.carbonModifiers = (try? container.decode(UInt32.self, forKey: .carbonModifiers)) ?? 0
        self.specialTrigger = (try? container.decode(HotkeySpecialTrigger.self, forKey: .specialTrigger)) ?? .none
        let storedDisplay = (try? container.decode(String.self, forKey: .displayString)) ?? ""
        if storedDisplay.isEmpty && carbonModifiers == 0 && specialTrigger == .none {
            self.displayString = ""
        } else {
            self.displayString = HotkeyDisplayFormatter.displayString(
                keyCode: keyCode,
                carbonModifiers: carbonModifiers,
                specialTrigger: specialTrigger
            )
        }
    }

    /// A cleared binding (keyCode 0 == 'A', no modifiers) must never be registered,
    /// otherwise the bare A key becomes a system-wide hotkey.
    public var isUnassigned: Bool {
        return specialTrigger == .none && carbonModifiers == 0 && displayString.isEmpty
    }

    public static let defaultShelf = HotkeyBinding(
        keyCode: 0, // Key 'A'
        carbonModifiers: 2048, // optionKey in Carbon
        displayString: "⌥A",
        specialTrigger: .none
    )

    public static let defaultSearch = HotkeyBinding(
        keyCode: 49, // Key 'Space'
        carbonModifiers: 2048, // optionKey in Carbon
        displayString: "⌥Space",
        specialTrigger: .none
    )
}

public enum AppTheme: String, Codable, CaseIterable {
    case liquidDark = "liquidDark"     // 液态玻璃 (深色)
    case liquidLight = "liquidLight"   // 液态玻璃 (浅色)

    /// Maps stored values, including the retired "经典纯色" themes, onto the remaining ones.
    public static func migrated(from rawValue: String) -> AppTheme? {
        switch rawValue {
        case "liquidDark", "solidDark": return .liquidDark
        case "liquidLight", "solidLight": return .liquidLight
        default: return nil
        }
    }

    public var title: String {
        switch self {
        case .liquidDark: return "液态玻璃 (深色)"
        case .liquidLight: return "液态玻璃 (浅色)"
        }
    }

    public var isDark: Bool {
        return self == .liquidDark
    }
}

public enum ShelfTrackpadGesture: String, Codable, CaseIterable {
    case none = "none"
    case fourFingerTap = "fourFingerTap"
    case threeFingerTap = "threeFingerTap"
    case threeFingerSwipeDown = "threeFingerSwipeDown"

    public var title: String {
        switch self {
        case .none: return "关闭"
        case .fourFingerTap: return "四指轻点 (推荐零冲突)"
        case .threeFingerTap: return "三指轻点"
        case .threeFingerSwipeDown: return "三指下滑"
        }
    }
}

public enum CategoryOrientation: String, Codable {
    case horizontal
    case vertical
}

/// 关窗即退的作用范围。名单 (`autoQuitAppRules`) 存 bundleID：
/// allApps 模式下为排除项，onlyListed 模式下为包含项。
public enum AutoQuitMode: String, Codable, CaseIterable {
    case allApps
    case onlyListed

    public var title: String {
        switch self {
        case .allApps: return "全部应用 (名单为排除项)"
        case .onlyListed: return "仅名单内应用"
        }
    }
}

public enum ShelfIconSize: String, Codable {
    case small
    case medium
    case large

    public var itemSize: CGFloat {
        switch self {
        case .small: return 68
        case .medium: return 82
        case .large: return 96
        }
    }

    public var iconSize: CGFloat {
        switch self {
        case .small: return 36
        case .medium: return 48
        case .large: return 60
        }
    }

    public var fontSize: CGFloat {
        switch self {
        case .small: return 10
        case .medium: return 11
        case .large: return 12
        }
    }
}

public extension CharacterSet {
    /// `.urlQueryAllowed` keeps `&`, `=`, `+` and `?` unescaped, which splits a query such as
    /// "C++ & Java" into several parameters. Values must escape those as well.
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+?#/")
        return set
    }()
}

public enum WebSearchEngine: String, Codable, CaseIterable {
    case google = "google"
    case bing = "bing"
    case baidu = "baidu"
    case duckduckgo = "duckduckgo"
    case custom = "custom"

    public var title: String {
        switch self {
        case .google: return "谷歌 (Google)"
        case .bing: return "微软必应 (Bing)"
        case .baidu: return "百度 (Baidu)"
        case .duckduckgo: return "DuckDuckGo"
        case .custom: return "自定义 (Custom URL)"
        }
    }

    public func searchURL(for query: String, customTemplate: String = "") -> URL? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) else { return nil }
        let urlStr: String
        switch self {
        case .google: urlStr = "https://www.google.com/search?q=\(encoded)"
        case .bing: urlStr = "https://www.bing.com/search?q=\(encoded)"
        case .baidu: urlStr = "https://www.baidu.com/s?wd=\(encoded)"
        case .duckduckgo: urlStr = "https://duckduckgo.com/?q=\(encoded)"
        case .custom:
            var template = customTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            if template.isEmpty {
                template = "https://www.google.com/search?q={query}"
            }
            if !template.lowercased().hasPrefix("http://") && !template.lowercased().hasPrefix("https://") {
                template = "https://" + template
            }
            if template.contains("{query}") {
                urlStr = template.replacingOccurrences(of: "{query}", with: encoded)
            } else if template.contains("%s") {
                urlStr = template.replacingOccurrences(of: "%s", with: encoded)
            } else {
                if template.contains("?") {
                    urlStr = (template.hasSuffix("&") || template.hasSuffix("=")) ? "\(template)\(encoded)" : "\(template)&q=\(encoded)"
                } else {
                    urlStr = "\(template)?q=\(encoded)"
                }
            }
        }
        return URL(string: urlStr)
    }
}

public struct AtoolsConfig: Codable {
    public var version: Int
    public var shelfHotkey: HotkeyBinding
    public var searchHotkey: HotkeyBinding
    public var categories: [Category]
    public var enableCalculator: Bool
    public var enableDictionary: Bool
    public var enableFullDiskSearch: Bool
    public var searchResultLimit: Int
    public var shelfWidth: Double
    public var shelfHeight: Double
    public var categoryOrientation: CategoryOrientation
    public var shelfIconSize: ShelfIconSize
    public var sidebarWidth: Double
    public var theme: AppTheme
    public var shelfIconScale: Double
    public var themeOpacity: Double

    // Panel Toggles and Auto-Close Behavior
    public var enableShelfPanel: Bool
    public var enableSearchPanel: Bool
    public var enableFavoritesCategory: Bool
    public var isShelfPinned: Bool
    public var autoCloseOnLaunch: Bool
    public var autoCloseOnMouseExit: Bool
    public var autoCloseOnDeactivate: Bool
    public var shelfTrackpadGesture: ShelfTrackpadGesture

    // Modern Settings & Performance extensions
    public var webSearchEngine: WebSearchEngine
    public var enableWebSearch: Bool
    public var customWebSearchURL: String
    public var memoryAnnealDelay: Double
    public var searchDebounceMs: Int
    public var thumbnailCacheLimitMB: Int
    /// 用户自定义热目录（绝对路径）。仅进内存快照（深度3层、每目录上限25,000条），
    /// 不影响全盘检索范围；卸载的卷会保留在配置里，重新挂载后自动生效。
    public var extraHotFolders: [String]
    public var searchFilterOrder: [String]

    // 全盘搜索范围排除预设 (对齐 Alfred Search Scope 设计)
    public var searchExcludeCaches: Bool          // 系统与应用缓存 (如 ~/Library/Caches)
    public var searchExcludeLogs: Bool            // 系统日志与诊断报告 (如 ~/Library/Logs, /var/log)
    public var searchExcludeDeveloper: Bool       // 开发者工程构建与依赖产物 (如 node_modules, DerivedData, .build, target)
    public var searchExcludeHidden: Bool          // 版本控制与隐藏文件 (如 .git, .* 隐藏项)
    public var searchExcludeTrash: Bool           // 废纸篓与临时目录 (如 ~/.Trash, /tmp)
    public var searchExcludeUserLibrary: Bool     // 排除 ~/Library 根目录 (智能保留 iCloud 云盘与第三方网盘)
    public var customExcludedPaths: [String]      // 用户自定义排除目录 (绝对路径列表)
    public var autoPasteOnSummonAfterCopy: Bool   // 复制后短时间内唤出全盘搜索自动粘贴

    // 关窗即退 (AutoQuit)：最后一个窗口关闭后延迟退出应用
    public var enableAutoQuit: Bool
    public var autoQuitMode: AutoQuitMode
    public var autoQuitExcludeAppRules: [String]      // .allApps 排除名单
    public var autoQuitOnlyListedAppRules: [String]   // .onlyListed 白名单退出名单
    public var autoQuitDelaySeconds: Int

    public func rules(for mode: AutoQuitMode) -> [String] {
        switch mode {
        case .allApps: return autoQuitExcludeAppRules
        case .onlyListed: return autoQuitOnlyListedAppRules
        }
    }

    public var currentAutoQuitAppRules: [String] {
        return rules(for: autoQuitMode)
    }

    /// 向下兼容旧调用与测试用例访问器
    public var autoQuitAppRules: [String] {
        get { currentAutoQuitAppRules }
        set {
            switch autoQuitMode {
            case .allApps: autoQuitExcludeAppRules = newValue
            case .onlyListed: autoQuitOnlyListedAppRules = newValue
            }
        }
    }

    public init(
        version: Int = 4,
        shelfHotkey: HotkeyBinding = .defaultShelf,
        searchHotkey: HotkeyBinding = .defaultSearch,
        categories: [Category] = [],
        enableCalculator: Bool = true,
        enableDictionary: Bool = true,
        enableFullDiskSearch: Bool = true,
        searchResultLimit: Int = 80,
        shelfWidth: Double = 540,
        shelfHeight: Double = 360,
        categoryOrientation: CategoryOrientation = .horizontal,
        shelfIconSize: ShelfIconSize = .medium,
        sidebarWidth: Double = 84,
        theme: AppTheme = .liquidDark,
        shelfIconScale: Double = 1.0,
        themeOpacity: Double = 0.90,
        enableShelfPanel: Bool = true,
        enableSearchPanel: Bool = true,
        enableFavoritesCategory: Bool = false,
        isShelfPinned: Bool = false,
        autoCloseOnLaunch: Bool = true,
        autoCloseOnMouseExit: Bool = false,
        autoCloseOnDeactivate: Bool = true,
        shelfTrackpadGesture: ShelfTrackpadGesture = .none,
        webSearchEngine: WebSearchEngine = .google,
        enableWebSearch: Bool = true,
        customWebSearchURL: String = "https://www.google.com/search?q={query}",
        memoryAnnealDelay: Double = 3.0,
        searchDebounceMs: Int = 150,
        thumbnailCacheLimitMB: Int = 6,
        extraHotFolders: [String] = [],
        searchFilterOrder: [String] = SearchTypeFilter.defaultOrderStrings,
        searchExcludeCaches: Bool = true,
        searchExcludeLogs: Bool = true,
        searchExcludeDeveloper: Bool = true,
        searchExcludeHidden: Bool = true,
        searchExcludeTrash: Bool = true,
        searchExcludeUserLibrary: Bool = true,
        customExcludedPaths: [String] = [],
        autoPasteOnSummonAfterCopy: Bool = false,
        enableAutoQuit: Bool = false,
        autoQuitMode: AutoQuitMode = .allApps,
        autoQuitAppRules: [String]? = nil,
        autoQuitExcludeAppRules: [String] = [],
        autoQuitOnlyListedAppRules: [String] = [],
        autoQuitDelaySeconds: Int = 2
    ) {
        self.version = version
        self.shelfHotkey = shelfHotkey
        self.searchHotkey = searchHotkey
        self.categories = categories
        self.enableCalculator = enableCalculator
        self.enableDictionary = enableDictionary
        self.enableFullDiskSearch = enableFullDiskSearch
        self.searchResultLimit = searchResultLimit
        self.shelfWidth = shelfWidth
        self.shelfHeight = shelfHeight
        self.categoryOrientation = categoryOrientation
        self.shelfIconSize = shelfIconSize
        self.sidebarWidth = sidebarWidth
        self.theme = theme
        self.shelfIconScale = shelfIconScale
        self.themeOpacity = themeOpacity
        self.enableShelfPanel = enableShelfPanel
        self.enableSearchPanel = enableSearchPanel
        self.enableFavoritesCategory = enableFavoritesCategory
        self.isShelfPinned = isShelfPinned
        self.autoCloseOnLaunch = autoCloseOnLaunch
        self.autoCloseOnMouseExit = autoCloseOnMouseExit
        self.autoCloseOnDeactivate = autoCloseOnDeactivate
        self.shelfTrackpadGesture = shelfTrackpadGesture
        self.webSearchEngine = webSearchEngine
        self.enableWebSearch = enableWebSearch
        self.customWebSearchURL = customWebSearchURL
        self.memoryAnnealDelay = memoryAnnealDelay
        self.searchDebounceMs = searchDebounceMs
        self.thumbnailCacheLimitMB = thumbnailCacheLimitMB
        self.extraHotFolders = extraHotFolders
        self.searchFilterOrder = searchFilterOrder
        self.searchExcludeCaches = searchExcludeCaches
        self.searchExcludeLogs = searchExcludeLogs
        self.searchExcludeDeveloper = searchExcludeDeveloper
        self.searchExcludeHidden = searchExcludeHidden
        self.searchExcludeTrash = searchExcludeTrash
        self.searchExcludeUserLibrary = searchExcludeUserLibrary
        self.customExcludedPaths = customExcludedPaths
        self.autoPasteOnSummonAfterCopy = autoPasteOnSummonAfterCopy
        self.enableAutoQuit = enableAutoQuit
        self.autoQuitMode = autoQuitMode
        if let legacy = autoQuitAppRules {
            if autoQuitMode == .onlyListed {
                self.autoQuitOnlyListedAppRules = legacy
                self.autoQuitExcludeAppRules = autoQuitExcludeAppRules
            } else {
                self.autoQuitExcludeAppRules = legacy
                self.autoQuitOnlyListedAppRules = autoQuitOnlyListedAppRules
            }
        } else {
            self.autoQuitExcludeAppRules = autoQuitExcludeAppRules
            self.autoQuitOnlyListedAppRules = autoQuitOnlyListedAppRules
        }
        self.autoQuitDelaySeconds = autoQuitDelaySeconds
    }

    enum CodingKeys: String, CodingKey {
        case version, shelfHotkey, searchHotkey, categories
        case enableCalculator, enableDictionary, enableFullDiskSearch, searchResultLimit
        case shelfWidth, shelfHeight, categoryOrientation, shelfIconSize, sidebarWidth
        case theme, shelfIconScale, themeOpacity
        case enableShelfPanel, enableSearchPanel, enableFavoritesCategory
        case isShelfPinned
        case autoCloseOnLaunch, autoCloseOnMouseExit, autoCloseOnDeactivate, shelfTrackpadGesture
        case webSearchEngine, enableWebSearch, customWebSearchURL, memoryAnnealDelay, searchDebounceMs, thumbnailCacheLimitMB
        case extraHotFolders, searchFilterOrder
        case searchExcludeCaches, searchExcludeLogs, searchExcludeDeveloper, searchExcludeHidden, searchExcludeTrash, searchExcludeUserLibrary, customExcludedPaths
        case autoPasteOnSummonAfterCopy
        case enableAutoQuit, autoQuitMode, autoQuitAppRules, autoQuitExcludeAppRules, autoQuitOnlyListedAppRules, autoQuitDelaySeconds
        // v1 legacy keys
        case globalHotkeyKey, globalHotkeyModifiers, hotkeyDescription
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = (try? container.decode(Int.self, forKey: .version)) ?? 4
        self.categories = (try? container.decode([Category].self, forKey: .categories)) ?? []
        self.enableCalculator = (try? container.decode(Bool.self, forKey: .enableCalculator)) ?? true
        self.enableDictionary = (try? container.decode(Bool.self, forKey: .enableDictionary)) ?? true
        self.enableFullDiskSearch = (try? container.decode(Bool.self, forKey: .enableFullDiskSearch)) ?? true
        self.searchResultLimit = (try? container.decode(Int.self, forKey: .searchResultLimit)) ?? 80
        self.shelfWidth = (try? container.decode(Double.self, forKey: .shelfWidth)) ?? 540
        self.shelfHeight = (try? container.decode(Double.self, forKey: .shelfHeight)) ?? 360
        self.categoryOrientation = (try? container.decode(CategoryOrientation.self, forKey: .categoryOrientation)) ?? .horizontal
        self.shelfIconSize = (try? container.decode(ShelfIconSize.self, forKey: .shelfIconSize)) ?? .medium
        self.sidebarWidth = (try? container.decode(Double.self, forKey: .sidebarWidth)) ?? 84
        let rawTheme = (try? container.decode(String.self, forKey: .theme)) ?? ""
        self.theme = AppTheme.migrated(from: rawTheme) ?? .liquidDark
        let rawScale = (try? container.decode(Double.self, forKey: .shelfIconScale)) ?? 1.0
        self.shelfIconScale = max(0.70, min(1.30, rawScale))
        let rawOpacity = (try? container.decode(Double.self, forKey: .themeOpacity)) ?? 0.90
        self.themeOpacity = max(0.40, min(1.00, rawOpacity))

        // New fields with strict non-destructive fallback defaults
        self.enableShelfPanel = (try? container.decode(Bool.self, forKey: .enableShelfPanel)) ?? true
        self.enableSearchPanel = (try? container.decode(Bool.self, forKey: .enableSearchPanel)) ?? true
        self.enableFavoritesCategory = (try? container.decode(Bool.self, forKey: .enableFavoritesCategory)) ?? false
        self.isShelfPinned = (try? container.decode(Bool.self, forKey: .isShelfPinned)) ?? false
        self.autoCloseOnLaunch = (try? container.decode(Bool.self, forKey: .autoCloseOnLaunch)) ?? true
        self.autoCloseOnMouseExit = (try? container.decode(Bool.self, forKey: .autoCloseOnMouseExit)) ?? false
        self.autoCloseOnDeactivate = (try? container.decode(Bool.self, forKey: .autoCloseOnDeactivate)) ?? true
        self.shelfTrackpadGesture = (try? container.decode(ShelfTrackpadGesture.self, forKey: .shelfTrackpadGesture)) ?? .none

        self.webSearchEngine = (try? container.decode(WebSearchEngine.self, forKey: .webSearchEngine)) ?? .google
        self.enableWebSearch = (try? container.decode(Bool.self, forKey: .enableWebSearch)) ?? true
        self.customWebSearchURL = (try? container.decode(String.self, forKey: .customWebSearchURL)) ?? "https://www.google.com/search?q={query}"
        self.memoryAnnealDelay = (try? container.decode(Double.self, forKey: .memoryAnnealDelay)) ?? 3.0
        self.searchDebounceMs = (try? container.decode(Int.self, forKey: .searchDebounceMs)) ?? 150
        self.thumbnailCacheLimitMB = (try? container.decode(Int.self, forKey: .thumbnailCacheLimitMB)) ?? 6
        self.extraHotFolders = (try? container.decode([String].self, forKey: .extraHotFolders)) ?? []
        self.searchFilterOrder = (try? container.decode([String].self, forKey: .searchFilterOrder)) ?? SearchTypeFilter.defaultOrderStrings
        self.searchExcludeCaches = (try? container.decode(Bool.self, forKey: .searchExcludeCaches)) ?? true
        self.searchExcludeLogs = (try? container.decode(Bool.self, forKey: .searchExcludeLogs)) ?? true
        self.searchExcludeDeveloper = (try? container.decode(Bool.self, forKey: .searchExcludeDeveloper)) ?? true
        self.searchExcludeHidden = (try? container.decode(Bool.self, forKey: .searchExcludeHidden)) ?? true
        self.searchExcludeTrash = (try? container.decode(Bool.self, forKey: .searchExcludeTrash)) ?? true
        self.searchExcludeUserLibrary = (try? container.decode(Bool.self, forKey: .searchExcludeUserLibrary)) ?? true
        self.customExcludedPaths = (try? container.decode([String].self, forKey: .customExcludedPaths)) ?? []
        self.autoPasteOnSummonAfterCopy = (try? container.decode(Bool.self, forKey: .autoPasteOnSummonAfterCopy)) ?? false

        // AutoQuit: 缺字段落到安全默认（总开关关闭）；老配置向下兼容迁移
        self.enableAutoQuit = (try? container.decode(Bool.self, forKey: .enableAutoQuit)) ?? false
        self.autoQuitMode = (try? container.decode(AutoQuitMode.self, forKey: .autoQuitMode)) ?? .allApps

        let decodedExclude = try? container.decode([String].self, forKey: .autoQuitExcludeAppRules)
        let decodedOnlyListed = try? container.decode([String].self, forKey: .autoQuitOnlyListedAppRules)
        let legacyRules = (try? container.decode([String].self, forKey: .autoQuitAppRules)) ?? []

        if let ex = decodedExclude {
            self.autoQuitExcludeAppRules = ex
        } else if self.autoQuitMode == .allApps {
            self.autoQuitExcludeAppRules = legacyRules
        } else {
            self.autoQuitExcludeAppRules = []
        }

        if let only = decodedOnlyListed {
            self.autoQuitOnlyListedAppRules = only
        } else if self.autoQuitMode == .onlyListed {
            self.autoQuitOnlyListedAppRules = legacyRules
        } else {
            self.autoQuitOnlyListedAppRules = []
        }

        let rawAutoQuitDelay = (try? container.decode(Int.self, forKey: .autoQuitDelaySeconds)) ?? 2
        self.autoQuitDelaySeconds = max(0, min(10, rawAutoQuitDelay))

        if let shelf = try? container.decode(HotkeyBinding.self, forKey: .shelfHotkey) {
            self.shelfHotkey = shelf
        } else {
            self.shelfHotkey = .defaultShelf
        }

        if let search = try? container.decode(HotkeyBinding.self, forKey: .searchHotkey) {
            self.searchHotkey = search
        } else if let oldKey = try? container.decode(UInt32.self, forKey: .globalHotkeyKey),
                  let oldMods = try? container.decode(UInt32.self, forKey: .globalHotkeyModifiers),
                  let oldDesc = try? container.decode(String.self, forKey: .hotkeyDescription) {
            self.searchHotkey = HotkeyBinding(keyCode: oldKey, carbonModifiers: oldMods, displayString: oldDesc)
        } else {
            self.searchHotkey = .defaultSearch
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(shelfHotkey, forKey: .shelfHotkey)
        try container.encode(searchHotkey, forKey: .searchHotkey)
        try container.encode(categories, forKey: .categories)
        try container.encode(enableCalculator, forKey: .enableCalculator)
        try container.encode(enableDictionary, forKey: .enableDictionary)
        try container.encode(enableFullDiskSearch, forKey: .enableFullDiskSearch)
        try container.encode(searchResultLimit, forKey: .searchResultLimit)
        try container.encode(shelfWidth, forKey: .shelfWidth)
        try container.encode(shelfHeight, forKey: .shelfHeight)
        try container.encode(categoryOrientation, forKey: .categoryOrientation)
        try container.encode(shelfIconSize, forKey: .shelfIconSize)
        try container.encode(sidebarWidth, forKey: .sidebarWidth)
        try container.encode(theme, forKey: .theme)
        try container.encode(shelfIconScale, forKey: .shelfIconScale)
        try container.encode(themeOpacity, forKey: .themeOpacity)
        try container.encode(enableShelfPanel, forKey: .enableShelfPanel)
        try container.encode(enableSearchPanel, forKey: .enableSearchPanel)
        try container.encode(enableFavoritesCategory, forKey: .enableFavoritesCategory)
        try container.encode(isShelfPinned, forKey: .isShelfPinned)
        try container.encode(autoCloseOnLaunch, forKey: .autoCloseOnLaunch)
        try container.encode(autoCloseOnMouseExit, forKey: .autoCloseOnMouseExit)
        try container.encode(autoCloseOnDeactivate, forKey: .autoCloseOnDeactivate)
        try container.encode(shelfTrackpadGesture, forKey: .shelfTrackpadGesture)
        try container.encode(webSearchEngine, forKey: .webSearchEngine)
        try container.encode(enableWebSearch, forKey: .enableWebSearch)
        try container.encode(customWebSearchURL, forKey: .customWebSearchURL)
        try container.encode(memoryAnnealDelay, forKey: .memoryAnnealDelay)
        try container.encode(searchDebounceMs, forKey: .searchDebounceMs)
        try container.encode(thumbnailCacheLimitMB, forKey: .thumbnailCacheLimitMB)
        try container.encode(extraHotFolders, forKey: .extraHotFolders)
        try container.encode(searchFilterOrder, forKey: .searchFilterOrder)
        try container.encode(searchExcludeCaches, forKey: .searchExcludeCaches)
        try container.encode(searchExcludeLogs, forKey: .searchExcludeLogs)
        try container.encode(searchExcludeDeveloper, forKey: .searchExcludeDeveloper)
        try container.encode(searchExcludeHidden, forKey: .searchExcludeHidden)
        try container.encode(searchExcludeTrash, forKey: .searchExcludeTrash)
        try container.encode(searchExcludeUserLibrary, forKey: .searchExcludeUserLibrary)
        try container.encode(customExcludedPaths, forKey: .customExcludedPaths)
        try container.encode(enableAutoQuit, forKey: .enableAutoQuit)
        try container.encode(autoQuitMode, forKey: .autoQuitMode)
        try container.encode(autoQuitExcludeAppRules, forKey: .autoQuitExcludeAppRules)
        try container.encode(autoQuitOnlyListedAppRules, forKey: .autoQuitOnlyListedAppRules)
        try container.encode(currentAutoQuitAppRules, forKey: .autoQuitAppRules)
        try container.encode(autoQuitDelaySeconds, forKey: .autoQuitDelaySeconds)
    }
}
