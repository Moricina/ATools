import Foundation
import AppKit




public final class ConfigManager {
    public static let shared = ConfigManager()

    public static var overrideConfigURL: URL?

    @discardableResult
    public static func setupIsolatedTestEnvironment() -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("atools_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let testURL = tempDir.appendingPathComponent("config.json")
        ConfigManager.overrideConfigURL = testURL
        return tempDir
    }

    public private(set) var config: AtoolsConfig
    private var configURL: URL
    private var backupConfigURL: URL?
    private let fileManager = FileManager.default

    private init() {
        if let custom = ConfigManager.overrideConfigURL {
            self.configURL = custom
            self.config = ConfigManager.loadOrCreateDefault(from: custom)
            SpotlightBridge.shared.setExtraHotFolders(self.config.extraHotFolders)
            return
        }

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let atoolsDir = appSupport.appendingPathComponent("ATools", isDirectory: true)
        let legacyDir = appSupport.appendingPathComponent("atools", isDirectory: true)
        
        // 平滑迁移旧版配置：若存在旧版 atools 目录且新版 ATools 目录不存在，则执行迁移
        if !fileManager.fileExists(atPath: atoolsDir.path) {
            if fileManager.fileExists(atPath: legacyDir.path) {
                try? fileManager.copyItem(at: legacyDir, to: atoolsDir)
            } else {
                try? fileManager.createDirectory(at: atoolsDir, withIntermediateDirectories: true)
            }
        }
        
        self.configURL = atoolsDir.appendingPathComponent("config.json")
        self.config = ConfigManager.loadOrCreateDefault(from: self.configURL)
        // 启动时把自定义热目录推送给快照（后台读配置会与主线程写配置竞争，
        // 所以 SpotlightBridge 不直接读 ConfigManager，由这里和变更时推送）。
        SpotlightBridge.shared.setExtraHotFolders(self.config.extraHotFolders)
    }

    private static func loadOrCreateDefault(from url: URL) -> AtoolsConfig {
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(AtoolsConfig.self, from: data) {
            var cfg = decoded
            var needsSave = false
            // Migration for existing configs: if sidebarWidth is old wide default/dragged value (>= 88.0), migrate to new compact 84.0
            if cfg.sidebarWidth >= 88.0 {
                cfg.sidebarWidth = 84.0
                needsSave = true
            }
            // 确保如果配置为未启用常用，不留存常用分类数据
            if !cfg.enableFavoritesCategory && cfg.categories.contains(where: { $0.isFavorites }) {
                cfg.categories.removeAll(where: { $0.isFavorites })
                for i in 0..<cfg.categories.count {
                    cfg.categories[i].sortWeight = i
                }
                needsSave = true
            }
            if needsSave {
                if let encoded = try? JSONEncoder().encode(cfg) {
                    try? encoded.write(to: url, options: .atomic)
                }
            }
            return cfg
        }
        let defaultConfig = createDefaultConfig()
        if let encoded = try? JSONEncoder().encode(defaultConfig) {
            try? encoded.write(to: url, options: .atomic)
        }
        return defaultConfig
    }

    /// 动态检测扫描系统及本地最常用应用
    public static func detectCommonApplications() -> [LauncherItem] {
        var commonItems: [LauncherItem] = []
        let commonApps = [
            ("访达 (Finder)", "/System/Library/CoreServices/Finder.app"),
            ("Safari 浏览器", "/Applications/Safari.app"),
            ("终端 (Terminal)", "/System/Applications/Utilities/Terminal.app"),
            ("系统设置", "/System/Applications/System Settings.app"),
            ("备忘录", "/System/Applications/Notes.app"),
            ("微信", "/Applications/WeChat.app"),
            ("QQ", "/Applications/QQ.app"),
            ("Google Chrome", "/Applications/Google Chrome.app")
        ]
        for (name, path) in commonApps {
            if FileManager.default.fileExists(atPath: path) {
                commonItems.append(LauncherItem(
                    name: name,
                    itemType: .application,
                    target: path
                ))
                if commonItems.count >= AppConstants.commonApplicationsLimit {
                    break
                }
            }
        }
        return commonItems
    }

    public static func createDefaultConfig() -> AtoolsConfig {
        var categories: [Category] = []

        // 默认不启用常用分类，由用户在设置中显式开启后动态扫描生成

        // 1. 开发工具
        var devItems: [LauncherItem] = []
        let devCandidates = [
            ("Xcode", "/Applications/Xcode.app"),
            ("Visual Studio Code", "/Applications/Visual Studio Code.app"),
            ("iTerm", "/Applications/iTerm.app"),
            ("Sublime Text", "/Applications/Sublime Text.app")
        ]
        for (name, path) in devCandidates {
            if FileManager.default.fileExists(atPath: path) {
                devItems.append(LauncherItem(name: name, itemType: .application, target: path))
            }
        }
        categories.append(Category(name: "开发", iconSymbol: "hammer.fill", sortWeight: 0, items: devItems))

        // 2. 效率与实用工具
        categories.append(Category(name: "效率", iconSymbol: "bolt.fill", sortWeight: 1, items: []))
        categories.append(Category(name: "文件与脚本", iconSymbol: "folder.fill", sortWeight: 2, items: []))

        return AtoolsConfig(categories: categories, enableFavoritesCategory: false)
    }

    private var pendingSaveWorkItem: DispatchWorkItem?

    /// Coalesces writes: sliders, splitter drags and resize snapping used to encode and
    /// atomically rewrite config.json on the main thread for every mouse event.
    public func save() {
        pendingSaveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        pendingSaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Writes immediately (used on termination and by `flushPendingSave`).
    public func saveNow() {
        pendingSaveWorkItem?.cancel()
        pendingSaveWorkItem = nil
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(self.config)
            try data.write(to: self.configURL, options: .atomic)
        } catch {
            print("[ConfigManager] Failed to save config: \(error)")
        }
    }

    public func flushPendingSave() {
        guard pendingSaveWorkItem != nil else { return }
        saveNow()
    }

    /// 激活独立隔离的沙盒测试环境，完全不读写生产环境 config.json
    @discardableResult
    public func enableIsolatedTestEnvironment() -> URL {
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("atools_test_\(UUID().uuidString)")
        try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let testURL = tempDir.appendingPathComponent("config.json")
        self.backupConfigURL = self.configURL
        self.configURL = testURL
        let freshConfig = ConfigManager.createDefaultConfig()
        self.config = freshConfig
        self.saveNow()
        return tempDir
    }

    /// 销毁沙盒测试环境并复原生产配置路径与内存数据
    public func tearDownIsolatedTestEnvironment(tempDir: URL? = nil) {
        if let dir = tempDir {
            try? fileManager.removeItem(at: dir)
        }
        if let original = backupConfigURL {
            self.configURL = original
            self.config = ConfigManager.loadOrCreateDefault(from: original)
            self.backupConfigURL = nil
        }
    }

    public func updateCategories(_ newCategories: [Category]) {
        self.config.categories = newCategories
        save()
    }

    public func updateShelfHotkey(_ binding: HotkeyBinding) {
        self.config.shelfHotkey = binding
        save()
    }

    public func updateSearchHotkey(_ binding: HotkeyBinding) {
        self.config.searchHotkey = binding
        save()
    }

    public func updateShelfSize(width: Double, height: Double) {
        let clampedW = max(240, min(1400, width))
        let clampedH = max(180, min(900, height))
        self.config.shelfWidth = clampedW
        self.config.shelfHeight = clampedH
        save()
    }

    public func updateCategoryOrientation(_ orientation: CategoryOrientation) {
        self.config.categoryOrientation = orientation
        save()
    }

    public func updateSidebarWidth(_ width: Double) {
        let clamped = max(50, min(240, width))
        self.config.sidebarWidth = clamped
        save()
    }

    public func updateShelfIconSize(_ size: ShelfIconSize) {
        self.config.shelfIconSize = size
        save()
    }

    public func updateTheme(_ theme: AppTheme) {
        self.config.theme = theme
        save()
        NotificationCenter.default.post(name: .atoolsThemeDidChange, object: nil)
    }

    public func updateThemeOpacity(_ opacity: Double) {
        let clamped = max(0.40, min(1.00, opacity))
        self.config.themeOpacity = clamped
        save()
        NotificationCenter.default.post(name: .atoolsThemeDidChange, object: nil)
    }

    public func updateShelfIconScale(_ scale: Double) {
        let clamped = max(0.70, min(1.30, scale))
        self.config.shelfIconScale = clamped
        if clamped <= 0.85 {
            self.config.shelfIconSize = .small
        } else if clamped >= 1.15 {
            self.config.shelfIconSize = .large
        } else {
            self.config.shelfIconSize = .medium
        }
        save()
    }

    public func updateEnableDictionary(_ enabled: Bool) {
        self.config.enableDictionary = enabled
        save()
    }

    public func updateEnableCalculator(_ enabled: Bool) {
        self.config.enableCalculator = enabled
        save()
    }

    public func updateEnableFullDiskSearch(_ enabled: Bool) {
        self.config.enableFullDiskSearch = enabled
        save()
    }

    // MARK: - 自定义热目录

    public static let maxExtraHotFolders = 8

    /// 校验自定义热目录路径；通过返回 standardized 路径，不合法返回 nil。
    /// 规则：必须是存在的绝对路径目录；拒绝家目录及其祖先（防止单个目录吃掉全盘）；
    /// 拒绝与默认热目录或已有项重复/互相包含；拒绝废纸篓。
    public func validatedHotFolderPath(_ rawPath: String) -> String? {
        let path = (rawPath as NSString).standardizingPath
        guard path.hasPrefix("/") else { return nil }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }

        let home = FileManager.default.homeDirectoryForCurrentUser
        // 根路径特殊处理：path=="/" 时拼前缀是 "//"，会漏过祖先判断
        let prefix = path.hasSuffix("/") ? path : path + "/"
        if home.path == path || home.path.hasPrefix(prefix) { return nil }
        if path.contains("/.Trash") { return nil }

        for name in SpotlightBridge.defaultHotFolders {
            if home.appendingPathComponent(name).path == path { return nil }
        }
        for existing in config.extraHotFolders {
            if existing == path
                || existing.hasPrefix(path + "/")
                || path.hasPrefix(existing + "/") { return nil }
        }
        return path
    }

    @discardableResult
    public func addHotFolder(_ rawPath: String) -> Bool {
        guard let path = validatedHotFolderPath(rawPath) else { return false }
        guard !config.extraHotFolders.contains(path) else { return false }
        guard config.extraHotFolders.count < Self.maxExtraHotFolders else { return false }
        config.extraHotFolders.append(path)
        save()
        SpotlightBridge.shared.setExtraHotFolders(config.extraHotFolders)
        SpotlightBridge.shared.dropHotFolderCache()
        return true
    }

    public func removeHotFolder(_ rawPath: String) {
        let path = (rawPath as NSString).standardizingPath
        let before = config.extraHotFolders.count
        config.extraHotFolders.removeAll { $0 == path }
        guard config.extraHotFolders.count != before else { return }
        save()
        SpotlightBridge.shared.setExtraHotFolders(config.extraHotFolders)
        SpotlightBridge.shared.dropHotFolderCache()
    }

    @discardableResult
    public func updateEnableShelfPanel(_ enabled: Bool) -> Bool {
        // Safety guard: prevent disabling both panels
        if !enabled && !self.config.enableSearchPanel {
            return false
        }
        self.config.enableShelfPanel = enabled
        save()
        return true
    }

    @discardableResult
    public func updateEnableSearchPanel(_ enabled: Bool) -> Bool {
        // Safety guard: prevent disabling both panels
        if !enabled && !self.config.enableShelfPanel {
            return false
        }
        self.config.enableSearchPanel = enabled
        save()
        return true
    }

    public func updateEnableFavoritesCategory(_ enabled: Bool) {
        self.config.enableFavoritesCategory = enabled
        if enabled {
            // 开启后：重新检测扫描系统常用软件并加入为「常用」分类
            let detectedItems = ConfigManager.detectCommonApplications()
            if let idx = self.config.categories.firstIndex(where: { $0.isFavorites }) {
                self.config.categories[idx].items = detectedItems
            } else {
                let favoritesCategory = Category(
                    name: Category.favoritesName,
                    iconSymbol: Category.favoritesIcon,
                    sortWeight: 0,
                    items: detectedItems
                )
                self.config.categories.insert(favoritesCategory, at: 0)
                for i in 0..<self.config.categories.count {
                    self.config.categories[i].sortWeight = i
                }
            }
        } else {
            // 关闭后：彻底移除「常用」分类及其内部应用数据，不保留任何数据
            self.config.categories.removeAll(where: { $0.isFavorites })
            for i in 0..<self.config.categories.count {
                self.config.categories[i].sortWeight = i
            }
        }
        save()
    }

    public func updateIsShelfPinned(_ pinned: Bool) {
        self.config.isShelfPinned = pinned
        save()
    }

    public func updateAutoCloseOnLaunch(_ enabled: Bool) {
        self.config.autoCloseOnLaunch = enabled
        save()
    }

    public func updateAutoCloseOnMouseExit(_ enabled: Bool) {
        self.config.autoCloseOnMouseExit = enabled
        save()
    }

    public func updateAutoCloseOnDeactivate(_ enabled: Bool) {
        self.config.autoCloseOnDeactivate = enabled
        save()
    }

    public func updateShelfTrackpadGesture(_ gesture: ShelfTrackpadGesture) {
        self.config.shelfTrackpadGesture = gesture
        save()
        TrackpadGestureManager.shared.updateConfiguration(gesture)
    }

    // MARK: - 关窗即退 (AutoQuit)
    // 每次变更后广播 .atoolsAutoQuitDidChange：AutoQuitManager 据此全量重建监视集合，
    // 状态栏菜单与设置页据此同步勾选态。

    public func updateEnableAutoQuit(_ enabled: Bool) {
        self.config.enableAutoQuit = enabled
        save()
        NotificationCenter.default.post(name: .atoolsAutoQuitDidChange, object: nil)
    }

    public func updateAutoQuitMode(_ mode: AutoQuitMode) {
        self.config.autoQuitMode = mode
        save()
        NotificationCenter.default.post(name: .atoolsAutoQuitDidChange, object: nil)
    }

    public func updateAutoQuitRules(_ rules: [String], for mode: AutoQuitMode? = nil) {
        let targetMode = mode ?? self.config.autoQuitMode
        switch targetMode {
        case .allApps:
            self.config.autoQuitExcludeAppRules = rules
        case .onlyListed:
            self.config.autoQuitOnlyListedAppRules = rules
        }
        save()
        NotificationCenter.default.post(name: .atoolsAutoQuitDidChange, object: nil)
    }

    public func updateAutoQuitDelaySeconds(_ seconds: Int) {
        let clamped = max(0, min(10, seconds))
        self.config.autoQuitDelaySeconds = clamped
        save()
        NotificationCenter.default.post(name: .atoolsAutoQuitDidChange, object: nil)
    }

    @discardableResult
    public func addItem(_ item: LauncherItem, to categoryId: UUID) -> Bool {
        addItems([item], to: categoryId).count == 1
    }

    /// Adds only new identities to a category. Duplicate drags are ignored, while the same
    /// target is still allowed in a different category for users who organize apps by context.
    @discardableResult
    public func addItems(_ items: [LauncherItem], to categoryId: UUID) -> [LauncherItem] {
        guard !items.isEmpty,
              let idx = self.config.categories.firstIndex(where: { $0.id == categoryId }) else { return [] }

        var seen = Set(self.config.categories[idx].items.map(\.identity))
        var added: [LauncherItem] = []
        for item in items where seen.insert(item.identity).inserted {
            added.append(item)
        }
        guard !added.isEmpty else { return [] }
        self.config.categories[idx].items.append(contentsOf: added)
        save()
        return added
    }

    public func moveCategory(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              self.config.categories.indices.contains(sourceIndex),
              destinationIndex >= 0, destinationIndex <= self.config.categories.count else { return }
        let moved = self.config.categories.remove(at: sourceIndex)
        let insertIndex = min(destinationIndex, self.config.categories.count)
        self.config.categories.insert(moved, at: insertIndex)
        for i in 0..<self.config.categories.count {
            self.config.categories[i].sortWeight = i
        }
        save()
    }

    public func moveItem(from sourceIndex: Int, to destinationIndex: Int, in categoryId: UUID) {
        guard let catIdx = self.config.categories.firstIndex(where: { $0.id == categoryId }) else { return }
        var items = self.config.categories[catIdx].items
        guard sourceIndex != destinationIndex,
              items.indices.contains(sourceIndex),
              destinationIndex >= 0, destinationIndex <= items.count else { return }
        let movedItem = items.remove(at: sourceIndex)
        let insertIndex = min(destinationIndex, items.count)
        items.insert(movedItem, at: insertIndex)
        self.config.categories[catIdx].items = items
        save()
    }

    /// Moves a launcher item between categories by its stable id, atomically removing it
    /// from the source category and appending it to the destination category.
    @discardableResult
    public func moveItem(id: UUID, toCategoryId destinationId: UUID) -> Bool {
        guard let sourceIdx = self.config.categories.firstIndex(where: { category in
            category.items.contains(where: { $0.id == id })
        }) else { return false }

        guard let destinationIdx = self.config.categories.firstIndex(where: { $0.id == destinationId }) else {
            return false
        }

        // No-op when dropping onto the category that already owns the item.
        guard sourceIdx != destinationIdx else { return false }

        guard let itemIndex = self.config.categories[sourceIdx].items.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let item = self.config.categories[sourceIdx].items.remove(at: itemIndex)
        self.config.categories[destinationIdx].items.append(item)
        save()
        return true
    }

    public func removeItem(id: UUID, from categoryId: UUID) {
        if let idx = self.config.categories.firstIndex(where: { $0.id == categoryId }) {
            self.config.categories[idx].items.removeAll(where: { $0.id == id })
            save()
        }
    }

    @discardableResult
    public func addCategory(name: String, iconSymbol: String = "folder.fill") -> Category {
        let newCat = Category(
            name: name,
            iconSymbol: iconSymbol,
            sortWeight: self.config.categories.count,
            items: []
        )
        self.config.categories.append(newCat)
        save()
        return newCat
    }

    public func renameCategory(id: UUID, newName: String, newIcon: String? = nil) {
        if let idx = self.config.categories.firstIndex(where: { $0.id == id }) {
            self.config.categories[idx].name = newName
            if let icon = newIcon {
                self.config.categories[idx].iconSymbol = icon
            }
            save()
        }
    }

    @discardableResult
    public func deleteCategory(id: UUID, migrateItemsTo targetId: UUID? = nil) -> Bool {
        guard self.config.categories.count > 1 else { return false }
        guard let idx = self.config.categories.firstIndex(where: { $0.id == id }) else { return false }

        let categoryToDelete = self.config.categories[idx]

        if let targetId = targetId,
           let targetIdx = self.config.categories.firstIndex(where: { $0.id == targetId }) {
            self.config.categories[targetIdx].items.append(contentsOf: categoryToDelete.items)
        }

        self.config.categories.remove(at: idx)
        for i in 0..<self.config.categories.count {
            self.config.categories[i].sortWeight = i
        }
        save()
        return true
    }

    public func updateWebSearchEngine(_ engine: WebSearchEngine) {
        self.config.webSearchEngine = engine
        save()
    }

    public func updateEnableWebSearch(_ enabled: Bool) {
        self.config.enableWebSearch = enabled
        save()
    }

    public func updateCustomWebSearchURL(_ url: String) {
        self.config.customWebSearchURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    public func updateSearchResultLimit(_ limit: Int) {
        let clamped = max(20, min(200, limit))
        self.config.searchResultLimit = clamped
        save()
    }

    public func updateMemoryAnnealDelay(_ delay: Double) {
        let clamped = max(1.0, min(30.0, delay))
        self.config.memoryAnnealDelay = clamped
        save()
    }

    public func updateSearchDebounceMs(_ ms: Int) {
        let clamped = max(30, min(500, ms))
        self.config.searchDebounceMs = clamped
        save()
    }

    public func updateThumbnailCacheLimitMB(_ mb: Int) {
        let clamped = max(2, min(64, mb))
        self.config.thumbnailCacheLimitMB = clamped
        ThumbnailPipeline.shared.updateCostLimit(mb: clamped)
        save()
    }
}
