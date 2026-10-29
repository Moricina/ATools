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

    /// 当前配置文件 URL
    public var currentConfigURL: URL {
        return configURL
    }

    /// 当前配置存储根目录（生产环境为 ~/Library/Application Support/ATools，测试环境为沙盒临时目录）
    public var storageDirectoryURL: URL {
        return configURL.deletingLastPathComponent()
    }

    /// 托管自定义图标目录（~/Library/Application Support/ATools/icons/）
    public var iconsDirectoryURL: URL {
        let dir = storageDirectoryURL.appendingPathComponent("icons", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 自动快照与备份目录（~/Library/Application Support/ATools/backups/）
    public var backupsDirectoryURL: URL {
        let dir = storageDirectoryURL.appendingPathComponent("backups", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private init() {
        if let custom = ConfigManager.overrideConfigURL {
            self.configURL = custom
            self.config = ConfigManager.loadOrCreateDefault(from: custom)
            SpotlightBridge.shared.setExtraHotFolders(self.config.extraHotFolders)
            SearchExclusionEngine.shared.recompile(config: self.config)
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
        SearchExclusionEngine.shared.recompile(config: self.config)
    }

    static func loadOrCreateDefault(from url: URL) -> AtoolsConfig {
        let storageDir = url.deletingLastPathComponent()
        let iconsDir = storageDir.appendingPathComponent("icons", isDirectory: true)
        let backupsDir = storageDir.appendingPathComponent("backups", isDirectory: true)

        if let data = try? Data(contentsOf: url) {
            do {
                let decoded = try JSONDecoder().decode(AtoolsConfig.self, from: data)
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
                    do {
                        let encoded = try JSONEncoder().encode(cfg)
                        try encoded.write(to: url, options: .atomic)
                    } catch {
                        runtimeLog("[ConfigManager] Failed to write migrated config: \(error)")
                    }
                }
                return cfg
            } catch {
                // 现场保全（绝对禁止直接覆写损坏的原始文件！）
                let fmt = DateFormatter()
                fmt.locale = Locale(identifier: "en_US_POSIX")
                fmt.dateFormat = "yyyyMMdd-HHmmss"
                let timestamp = fmt.string(from: Date())
                let corruptedURL = storageDir.appendingPathComponent("config.corrupted.\(timestamp).json")
                do {
                    try data.write(to: corruptedURL, options: .atomic)
                } catch {
                    runtimeLog("[ConfigManager] Failed to preserve corrupted config: \(error)")
                }
                runtimeLog("[ConfigManager] CRITICAL: config.json exists but decode failed: \(error.localizedDescription). Preserved corrupted data to: \(corruptedURL.lastPathComponent)")

                // 尝试从 BackupService 历史快照（pre-restore-* 与 ATools-Backup-*）中自动自愈恢复
                let snapshots = BackupService.shared.listPreRestoreSnapshots(in: backupsDir)
                for snapshotURL in snapshots {
                    if case .success(let validation) = BackupService.shared.validateBackup(
                        at: snapshotURL,
                        currentIconsDirOverride: iconsDir
                    ) {
                        let healedConfig = validation.healedConfig
                        do {
                            let encoded = try JSONEncoder().encode(healedConfig)
                            try encoded.write(to: url, options: .atomic)
                        } catch {
                            runtimeLog("[ConfigManager] Failed to write auto-healed config: \(error)")
                        }
                        // 还原图标
                        for (fileName, src) in validation.iconSourceFiles {
                            let dst = iconsDir.appendingPathComponent(fileName)
                            if let iconData = try? Data(contentsOf: src) {
                                try? iconData.write(to: dst, options: .atomic)
                            }
                        }
                        runtimeLog("[ConfigManager] Successfully auto-healed config and custom icons from snapshot: \(snapshotURL.lastPathComponent)")
                        return healedConfig
                    }
                }
                runtimeLog("[ConfigManager] WARNING: No valid backup snapshot found for auto-healing. Falling back to default config.")
            }
        }
        let defaultConfig = createDefaultConfig()
        do {
            let encoded = try JSONEncoder().encode(defaultConfig)
            try encoded.write(to: url, options: .atomic)
        } catch {
            runtimeLog("[ConfigManager] Failed to write default config: \(error)")
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

        return AtoolsConfig(categories: categories, theme: .macosLiquidLight, enableFavoritesCategory: false)
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
            let msg = "[ConfigManager] Failed to save config: \(error)"
            print(msg)
            runtimeLog(msg)
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
        self.config.themeOpacity = theme.defaultOpacity
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
        let clamped = max(0.70, min(1.10, scale))
        self.config.shelfIconScale = clamped
        if clamped <= 0.85 {
            self.config.shelfIconSize = .small
        } else if clamped >= 1.05 {
            self.config.shelfIconSize = .large
        } else {
            self.config.shelfIconSize = .medium
        }
        save()
    }

    public func updateShelfItemSpacing(_ spacing: Double) {
        let clamped = max(2.0, min(24.0, spacing))
        self.config.shelfItemSpacing = clamped
        save()
        NotificationCenter.default.post(name: .atoolsShelfItemSpacingDidChange, object: nil)
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

    public func updateAutoPasteOnSummonAfterCopy(_ enabled: Bool) {
        self.config.autoPasteOnSummonAfterCopy = enabled
        save()
        NotificationCenter.default.post(name: .atoolsAutoPasteOnSummonDidChange, object: nil)
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

    // MARK: - 全盘搜索排除范围管理 (对齐 Alfred Search Scope 设计)

    public static let maxCustomExcludedPaths = 32

    /// 校验自定义排除目录路径。合法返回标准化绝对路径，不合法返回 nil。
    /// 防御规则：必须为存在的绝对目录；禁止根目录 / 与家目录 ~（防止一键排除全盘或全部个人文件）；
    public func validatedExcludedFolderPath(_ rawPath: String) -> String? {
        let path = (rawPath as NSString).standardizingPath
        guard path.hasPrefix("/") else { return nil }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == "/" || path == home { return nil }

        return path
    }

    /// 添加自定义排除目录（带子目录包含吸收与去重）
    @discardableResult
    public func addCustomExcludedPath(_ rawPath: String) -> Bool {
        guard let path = validatedExcludedFolderPath(rawPath) else { return false }
        guard !config.customExcludedPaths.contains(path) else { return false }

        // 若已有路径是当前新路径的父级，则新路径已被覆盖，无需重复添加
        for existing in config.customExcludedPaths {
            if path.hasPrefix(existing + "/") { return false }
        }

        // 若新路径是已有某些路径的父级，则自动吸收清理冗余的子路径
        config.customExcludedPaths.removeAll { existing in
            existing.hasPrefix(path + "/")
        }

        guard config.customExcludedPaths.count < Self.maxCustomExcludedPaths else { return false }
        config.customExcludedPaths.append(path)
        save()
        SearchExclusionEngine.shared.recompile(config: config)
        SpotlightBridge.shared.dropHotFolderCache()
        return true
    }

    public func removeCustomExcludedPath(_ rawPath: String) {
        let path = (rawPath as NSString).standardizingPath
        let before = config.customExcludedPaths.count
        config.customExcludedPaths.removeAll { $0 == path }
        guard config.customExcludedPaths.count != before else { return }
        save()
        SearchExclusionEngine.shared.recompile(config: config)
        SpotlightBridge.shared.dropHotFolderCache()
    }

    public func resetCustomExcludedPathsToDefault() {
        config.customExcludedPaths = []
        save()
        SearchExclusionEngine.shared.recompile(config: config)
        SpotlightBridge.shared.dropHotFolderCache()
    }

    // 预设排除开关
    public func updateSearchExcludeCaches(_ enabled: Bool) {
        config.searchExcludeCaches = enabled
        save()
        SearchExclusionEngine.shared.recompile(config: config)
        SpotlightBridge.shared.dropHotFolderCache()
    }

    public func updateSearchExcludeLogs(_ enabled: Bool) {
        config.searchExcludeLogs = enabled
        save()
        SearchExclusionEngine.shared.recompile(config: config)
        SpotlightBridge.shared.dropHotFolderCache()
    }

    public func updateSearchExcludeDeveloper(_ enabled: Bool) {
        config.searchExcludeDeveloper = enabled
        save()
        SearchExclusionEngine.shared.recompile(config: config)
        SpotlightBridge.shared.dropHotFolderCache()
    }

    public func updateSearchExcludeHidden(_ enabled: Bool) {
        config.searchExcludeHidden = enabled
        save()
        SearchExclusionEngine.shared.recompile(config: config)
        SpotlightBridge.shared.dropHotFolderCache()
    }

    public func updateSearchExcludeTrash(_ enabled: Bool) {
        config.searchExcludeTrash = enabled
        save()
        SearchExclusionEngine.shared.recompile(config: config)
        SpotlightBridge.shared.dropHotFolderCache()
    }

    public func updateSearchExcludeUserLibrary(_ enabled: Bool) {
        config.searchExcludeUserLibrary = enabled
        save()
        SearchExclusionEngine.shared.recompile(config: config)
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
        if PanelCoordinator.shared.isShelfPanelCreated {
            PanelCoordinator.shared.shelfPanel.shelfViewController.updatePinButtonState(isPinned: pinned)
            if pinned {
                PanelCoordinator.shared.shelfPanel.shelfViewController.cancelPendingMouseExitAutoClose()
            } else if PanelCoordinator.shared.isShelfPanelVisible {
                PanelCoordinator.shared.shelfPanel.shelfViewController.beginMouseExitMonitoringOnShow()
            }
        }
        NotificationCenter.default.post(name: .atoolsShelfDataDidChange, object: nil)
    }

    public func updateAutoCloseOnLaunch(_ enabled: Bool) {
        self.config.autoCloseOnLaunch = enabled
        save()
    }

    public func updateEnableAutoAddInstalledApps(_ enabled: Bool) {
        self.config.enableAutoAddInstalledApps = enabled
        if enabled && self.config.knownAppBundleIds.isEmpty {
            // 立即沉淀基线，确保开启瞬间不灌水
            let regularApps = AppHotspotIndex.shared.allRegularApps
            let bids = regularApps.compactMap { $0.bundleId }.filter { !$0.isEmpty }
            self.config.knownAppBundleIds = Array(Set(bids)).sorted()
            self.config.lastAutoAppScanTimestamp = Date().timeIntervalSince1970
        }
        save()
    }

    public func updateAutoAddTargetPolicy(mode: AutoAddPolicyMode, categoryId: UUID?, inboxName: String? = nil) {
        self.config.autoAddPolicyMode = mode
        self.config.autoAddTargetCategoryId = categoryId
        if let name = inboxName, !name.isEmpty {
            self.config.autoAddInboxCategoryName = name
        }
        save()
        NotificationCenter.default.post(name: .atoolsShelfDataDidChange, object: nil)
    }

    public func updateKnownAppBundleIds(_ ids: [String]) {
        self.config.knownAppBundleIds = ids
        save()
    }

    public func updateEnableQuickSlots(_ enabled: Bool) {
        self.config.enableQuickSlots = enabled
        save()
        NotificationCenter.default.post(name: .atoolsShelfDataDidChange, object: nil)
    }

    public func updateAutoCloseOnMouseExit(_ enabled: Bool) {
        self.config.autoCloseOnMouseExit = enabled
        save()
        if enabled {
            if PanelCoordinator.shared.isShelfPanelVisible {
                PanelCoordinator.shared.shelfPanel.shelfViewController.beginMouseExitMonitoringOnShow()
            }
        } else if PanelCoordinator.shared.isShelfPanelCreated {
            PanelCoordinator.shared.shelfPanel.shelfViewController.stopMouseExitMonitoring()
        }
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

    public func updateEnableAutoQuitUndoHUD(_ enabled: Bool) {
        self.config.enableAutoQuitUndoHUD = enabled
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

    /// Returns visible root items and their children as stable movable blocks.
    private func rootItemBlocks(_ items: [LauncherItem]) -> [[LauncherItem]] {
        let folderIds = Set(items.filter(\.isVirtualGroup).map(\.id))
        var normalizedItems = items
        for itemIndex in normalizedItems.indices {
            if let parentId = normalizedItems[itemIndex].parentId, !folderIds.contains(parentId) {
                normalizedItems[itemIndex].parentId = nil
            }
        }
        let roots = normalizedItems.filter { $0.parentId == nil }
        return roots.map { root in
            guard root.isVirtualGroup else { return [root] }
            return [root] + normalizedItems.filter { $0.parentId == root.id }
        }
    }

    /// Root indices are measured against the visible top-level shelf, not the backing array.
    public func moveItem(from sourceIndex: Int, to destinationIndex: Int, in categoryId: UUID) {
        guard let catIdx = self.config.categories.firstIndex(where: { $0.id == categoryId }) else { return }
        var blocks = rootItemBlocks(self.config.categories[catIdx].items)
        guard sourceIndex != destinationIndex,
              blocks.indices.contains(sourceIndex),
              destinationIndex >= 0, destinationIndex <= blocks.count else { return }
        let movedBlock = blocks.remove(at: sourceIndex)
        blocks.insert(movedBlock, at: min(destinationIndex, blocks.count))
        self.config.categories[catIdx].items = blocks.flatMap { $0 }
        if self.config.shelfSortPolicy != .manual {
            self.config.shelfSortPolicy = .manual
        }
        save()
    }

    /// Alt/Option 快速交换模式：按可见根节点直接交换两个项目块，其余项目位置保持不变。
    public func swapItems(at indexA: Int, and indexB: Int, in categoryId: UUID) {
        guard let catIdx = self.config.categories.firstIndex(where: { $0.id == categoryId }) else { return }
        var blocks = rootItemBlocks(self.config.categories[catIdx].items)
        guard indexA != indexB,
              blocks.indices.contains(indexA),
              blocks.indices.contains(indexB) else { return }
        blocks.swapAt(indexA, indexB)
        self.config.categories[catIdx].items = blocks.flatMap { $0 }
        if self.config.shelfSortPolicy != .manual {
            self.config.shelfSortPolicy = .manual
        }
        save()
    }

    /// Moves an item or virtual-folder block between categories. destinationIndex is a visible root slot.
    @discardableResult
    public func moveItem(id: UUID, toCategoryId destinationId: UUID, at destinationIndex: Int? = nil) -> Bool {
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

        let sourceItems = self.config.categories[sourceIdx].items
        let item = sourceItems[itemIndex]
        let movingIds: Set<UUID> = item.isVirtualGroup
            ? Set([item.id] + sourceItems.filter { $0.parentId == item.id }.map(\.id))
            : [item.id]
        var movingBlock = item.isVirtualGroup
            ? [item] + sourceItems.filter { $0.parentId == item.id }
            : [item]
        if !item.isVirtualGroup {
            movingBlock[0].parentId = nil
        }
        self.config.categories[sourceIdx].items.removeAll { movingIds.contains($0.id) }

        var destinationBlocks = rootItemBlocks(self.config.categories[destinationIdx].items)
        let slot = max(0, min(destinationIndex ?? destinationBlocks.count, destinationBlocks.count))
        destinationBlocks.insert(movingBlock, at: slot)
        self.config.categories[destinationIdx].items = destinationBlocks.flatMap { $0 }
        save()
        return true
    }

    public func removeItem(id: UUID, from categoryId: UUID) {
        removeItems(ids: [id], from: categoryId)
    }

    /// 原子批量移除启动项（单次写锁、单次存盘、单次广播、统一 Tombstone 墓碑化防复活）
    public func removeItems(ids: Set<UUID>, from categoryId: UUID) {
        guard !ids.isEmpty else { return }
        guard let idx = self.config.categories.firstIndex(where: { $0.id == categoryId }) else { return }

        let removed = self.config.categories[idx].items.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }

        // 级联清理：若移除的项中包含虚拟组（文件夹），级联移除所有归属其下的子项
        var allIdsToRemove = ids
        let groupIds = Set(removed.filter { $0.isVirtualGroup }.map { $0.id })
        if !groupIds.isEmpty {
            let subItems = self.config.categories[idx].items.filter { sub in
                if let p = sub.parentId, groupIds.contains(p) { return true }
                return false
            }
            for sub in subItems {
                allIdsToRemove.insert(sub.id)
                removeManagedIconIfUnused(sub.customIconPath, excludingItemId: sub.id)
                ThumbnailPipeline.shared.invalidateIcon(forItem: sub)
            }
            self.config.categories[idx].items.removeAll(where: { sub in
                if let p = sub.parentId, groupIds.contains(p) { return true }
                return false
            })
        }

        self.config.categories[idx].items.removeAll(where: { allIdsToRemove.contains($0.id) })
        for item in removed {
            removeManagedIconIfUnused(item.customIconPath, excludingItemId: item.id)
            ThumbnailPipeline.shared.invalidateIcon(forItem: item)
            // 记录 Tombstone，防新装应用监听将其误当作“新应用”再次复活
            if item.itemType == .application {
                if let bid = Bundle(path: item.target)?.bundleIdentifier {
                    if !self.config.ignoredAutoAddBundleIds.contains(bid) {
                        self.config.ignoredAutoAddBundleIds.append(bid)
                    }
                }
            }
        }
        save()
        NotificationCenter.default.post(name: .atoolsShelfDataDidChange, object: nil)
    }

    /// 原子批量跨分类迁移启动项
    public func moveItems(ids: Set<UUID>, from fromCategoryId: UUID, to toCategoryId: UUID) {
        guard !ids.isEmpty, fromCategoryId != toCategoryId else { return }
        guard let srcIdx = self.config.categories.firstIndex(where: { $0.id == fromCategoryId }),
              let dstIdx = self.config.categories.firstIndex(where: { $0.id == toCategoryId }) else { return }

        let movingItems = self.config.categories[srcIdx].items.filter { ids.contains($0.id) }
        guard !movingItems.isEmpty else { return }

        // 若迁移的项包含文件夹，同步将其子项一并迁入目标分类
        let groupIds = Set(movingItems.filter { $0.isVirtualGroup }.map { $0.id })
        var subItemsToMove: [LauncherItem] = []
        if !groupIds.isEmpty {
            subItemsToMove = self.config.categories[srcIdx].items.filter { sub in
                if let p = sub.parentId, groupIds.contains(p) { return true }
                return false
            }
        }

        let allIdsToMove = ids.union(Set(subItemsToMove.map { $0.id }))
        self.config.categories[srcIdx].items.removeAll(where: { allIdsToMove.contains($0.id) })
        self.config.categories[dstIdx].items.append(contentsOf: movingItems)
        self.config.categories[dstIdx].items.append(contentsOf: subItemsToMove)

        save()
        NotificationCenter.default.post(name: .atoolsShelfDataDidChange, object: nil)
    }

    /// 将选中的多项原子化打包合并为新文件夹（禁止文件夹嵌套）
    @discardableResult
    public func createFolderWithItems(itemIds: Set<UUID>, inCategoryId: UUID, folderName: String = "未命名文件夹") -> LauncherItem? {
        guard itemIds.count >= 2 else { return nil }
        guard let catIdx = self.config.categories.firstIndex(where: { $0.id == inCategoryId }) else { return nil }

        let itemsToGroup = self.config.categories[catIdx].items.filter { itemIds.contains($0.id) }
        // 严格防嵌套：已选项目中若包含虚拟组（文件夹），直接拒绝
        if itemsToGroup.contains(where: { $0.isVirtualGroup }) { return nil }

        let folder = LauncherItem(
            name: folderName,
            itemType: .fileOrFolder,
            target: "",
            isVirtualGroup: true
        )

        let firstIdx = self.config.categories[catIdx].items.firstIndex(where: { itemIds.contains($0.id) }) ?? self.config.categories[catIdx].items.count

        for i in 0..<self.config.categories[catIdx].items.count {
            if itemIds.contains(self.config.categories[catIdx].items[i].id) {
                self.config.categories[catIdx].items[i].parentId = folder.id
            }
        }

        self.config.categories[catIdx].items.insert(folder, at: firstIdx)
        save()
        NotificationCenter.default.post(name: .atoolsShelfDataDidChange, object: nil)
        return folder
    }

    /// 解散指定文件夹，将其内部所有子项还原为当前分类的根节点项目，并移除该虚拟文件夹
    @discardableResult
    public func ungroupFolder(id: UUID, in categoryId: UUID) -> Bool {
        guard let catIdx = self.config.categories.firstIndex(where: { $0.id == categoryId }) else { return false }
        guard let folderIdx = self.config.categories[catIdx].items.firstIndex(where: { $0.id == id && $0.isVirtualGroup }) else { return false }

        for i in 0..<self.config.categories[catIdx].items.count {
            if self.config.categories[catIdx].items[i].parentId == id {
                self.config.categories[catIdx].items[i].parentId = nil
            }
        }
        self.config.categories[catIdx].items.remove(at: folderIdx)
        save()
        NotificationCenter.default.post(name: .atoolsShelfDataDidChange, object: nil)
        return true
    }

    // MARK: - 启动频次统计、智能常用推荐与多策略重排序

    public func updateTrackLaunchFrequency(_ enabled: Bool) {
        self.config.trackLaunchFrequency = enabled
        save()
    }

    public func updateShelfSortPolicy(_ policy: ShelfSortPolicy) {
        self.config.shelfSortPolicy = policy
        if policy != .manual {
            for cat in self.config.categories where !cat.isFavorites {
                sortItems(in: cat.id, by: policy, shouldSaveAndNotify: false)
            }
        }
        save()
        NotificationCenter.default.post(name: .atoolsShelfDataDidChange, object: nil)
    }

    public func recordItemLaunch(itemId: UUID) {
        guard config.trackLaunchFrequency else { return } // 🔒 隐私控制：关闭时不记录
        var didUpdate = false
        for catIdx in 0..<config.categories.count {
            if let itemIdx = config.categories[catIdx].items.firstIndex(where: { $0.id == itemId }) {
                config.categories[catIdx].items[itemIdx].launchCount += 1
                config.categories[catIdx].items[itemIdx].lastLaunchedAt = Date().timeIntervalSince1970
                didUpdate = true
                break
            }
        }
        if didUpdate {
            save()
            if config.enableFavoritesCategory && config.smartFavoritesMode {
                NotificationCenter.default.post(name: .atoolsShelfDataDidChange, object: nil)
            }
        }
    }

    /// 获取使用频率最高的启动项（智能常用推荐）
    public func frequentItems(limit: Int = 12) -> [LauncherItem] {
        var allItems: [LauncherItem] = []
        for cat in config.categories where !cat.isFavorites {
            for item in cat.items where !item.isVirtualGroup {
                allItems.append(item)
            }
        }
        let sorted = allItems.sorted { a, b in
            if a.launchCount != b.launchCount {
                return a.launchCount > b.launchCount
            }
            return (a.lastLaunchedAt ?? 0) > (b.lastLaunchedAt ?? 0)
        }
        return Array(sorted.prefix(limit))
    }

    /// 按启动频次（launchCount 降序，相同按 lastLaunchedAt 降序）重新排序指定分类内的项目
    public func sortItemsByFrequency(in categoryId: UUID) {
        sortItems(in: categoryId, by: .frequency)
    }

    /// 按照指定策略（频次 / 名称 A-Z / 最近添加）重新排序指定分类内的项目
    public func sortItems(in categoryId: UUID, by policy: ShelfSortPolicy, shouldSaveAndNotify: Bool = true) {
        guard let idx = self.config.categories.firstIndex(where: { $0.id == categoryId }) else { return }
        guard !self.config.categories[idx].isFavorites else { return }
        guard policy != .manual else { return }

        let items = self.config.categories[idx].items
        guard items.count > 1 else { return }

        func effectiveScore(of item: LauncherItem) -> (count: Int, lastTime: Double) {
            if item.isVirtualGroup {
                let children = items.filter { $0.parentId == item.id }
                let totalCount = children.reduce(0) { $0 + $1.launchCount }
                let latestTime = children.compactMap { $0.lastLaunchedAt }.max() ?? 0
                return (totalCount, latestTime)
            } else {
                return (item.launchCount, item.lastLaunchedAt ?? 0)
            }
        }

        func effectiveAddedAt(of item: LauncherItem) -> Double {
            if item.isVirtualGroup {
                let children = items.filter { $0.parentId == item.id }
                let maxChild = children.map { effectiveAddedAt(of: $0) }.max() ?? 0
                if maxChild > 0 { return maxChild }
                return item.addedAt ?? 0
            }
            if let at = item.addedAt, at > 0 {
                return at
            }
            if let attrs = try? FileManager.default.attributesOfItem(atPath: item.target),
               let date = attrs[.creationDate] as? Date {
                return date.timeIntervalSince1970
            }
            return 0
        }

        let comparator: (LauncherItem, LauncherItem) -> Bool = { a, b in
            switch policy {
            case .frequency:
                let scoreA = effectiveScore(of: a)
                let scoreB = effectiveScore(of: b)
                if scoreA.count != scoreB.count {
                    return scoreA.count > scoreB.count
                }
                if scoreA.lastTime != scoreB.lastTime {
                    return scoreA.lastTime > scoreB.lastTime
                }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending

            case .nameAscending:
                return a.name.localizedStandardCompare(b.name) == .orderedAscending

            case .recentlyAdded:
                let timeA = effectiveAddedAt(of: a)
                let timeB = effectiveAddedAt(of: b)
                if timeA != timeB {
                    return timeA > timeB
                }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending

            case .manual:
                return false
            }
        }

        let folderIds = Set(items.filter(\.isVirtualGroup).map(\.id))
        var normalizedItems = items
        for itemIndex in normalizedItems.indices {
            if let parentId = normalizedItems[itemIndex].parentId, !folderIds.contains(parentId) {
                // Preserve orphaned records by healing them into visible top-level items.
                normalizedItems[itemIndex].parentId = nil
            }
        }
        let rootItems = normalizedItems.filter { $0.parentId == nil }
        let sortedRoots = rootItems.sorted(by: comparator)

        var newOrderedItems: [LauncherItem] = []
        for root in sortedRoots {
            newOrderedItems.append(root)
            if root.isVirtualGroup {
                let children = normalizedItems.filter { $0.parentId == root.id }.sorted(by: comparator)
                newOrderedItems.append(contentsOf: children)
            }
        }


        self.config.categories[idx].items = newOrderedItems
        if shouldSaveAndNotify {
            save()
            NotificationCenter.default.post(name: .atoolsShelfDataDidChange, object: nil)
        }
    }

    // MARK: - 新安装应用自动入库 (Auto App Discovery & Onboarding)

    public func handleAppIndexUpdated(apps: [IndexedApp]) {
        guard config.enableAutoAddInstalledApps else { return }

        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.handleAppIndexUpdated(apps: apps)
            }
            return
        }

        var knownSet = Set(config.knownAppBundleIds)
        let isFirstBaselineSetup = knownSet.isEmpty

        // 收集本次扫描中所有合规本地应用的 Bundle ID
        var scannedValidBids = Set<String>()
        for app in apps {
            guard app.isRegularApp else { continue }
            let path = app.path
            guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { continue }
            if path.hasPrefix("/Volumes/") { continue }
            if let bid = app.bundleId, !bid.isEmpty {
                scannedValidBids.insert(bid)
            }
        }

        // 🌟 核心防线：首次初始化时（knownSet 为空），全量沉淀现有应用为已知基线，本次绝对不执行任何入库入抽屉动作！
        if isFirstBaselineSetup {
            config.knownAppBundleIds = Array(scannedValidBids).sorted()
            config.lastAutoAppScanTimestamp = Date().timeIntervalSince1970
            save()
            runtimeLog("[AutoDiscovery] Established baseline snapshot with \(config.knownAppBundleIds.count) known app(s). Zero apps injected.")
            return
        }

        var targetCatIdx: Int?

        if config.autoAddPolicyMode == .existingCategory,
           let targetId = config.autoAddTargetCategoryId,
           let idx = config.categories.firstIndex(where: { $0.id == targetId }) {
            targetCatIdx = idx
        } else {
            // 专属收件箱分类模式 (或目标分类被删除时的安全自愈)
            let inboxName = config.autoAddInboxCategoryName.isEmpty ? "新应用" : config.autoAddInboxCategoryName
            if let idx = config.categories.firstIndex(where: { $0.name == inboxName }) {
                targetCatIdx = idx
            } else {
                // 自动创建名为“新应用”的独立专属分类并带 sparkles 图标
                let newCat = Category(name: inboxName, iconSymbol: "sparkles", items: [])
                if let favIdx = config.categories.firstIndex(where: { $0.isFavorites }) {
                    config.categories.insert(newCat, at: favIdx + 1)
                    targetCatIdx = favIdx + 1
                } else {
                    config.categories.insert(newCat, at: 0)
                    targetCatIdx = 0
                }
            }
        }

        guard let targetIndex = targetCatIdx else { return }

        var existingTargets = Set<String>()
        for cat in config.categories {
            for item in cat.items {
                existingTargets.insert(item.target)
            }
        }

        let ignoredSet = Set(config.ignoredAutoAddBundleIds)
        var newlyAddedCount = 0

        for app in apps {
            guard app.isRegularApp else { continue }
            let path = app.path
            guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { continue }
            if path.hasPrefix("/Volumes/") { continue }

            guard let bid = app.bundleId, !bid.isEmpty else { continue }
            if knownSet.contains(bid) { continue }
            if ignoredSet.contains(bid) { continue }
            if existingTargets.contains(path) {
                knownSet.insert(bid)
                continue
            }

            // 完整性核验：主可执行二进制必须已落地
            if let executablePath = Bundle(path: path)?.executablePath,
               !FileManager.default.fileExists(atPath: executablePath) {
                continue
            }

            let newItem = LauncherItem(
                name: app.localizedName.isEmpty ? app.name : app.localizedName,
                itemType: .application,
                target: path
            )

            config.categories[targetIndex].items.append(newItem)
            existingTargets.insert(path)
            knownSet.insert(bid)
            newlyAddedCount += 1
        }

        config.knownAppBundleIds = Array(knownSet).sorted()
        config.lastAutoAppScanTimestamp = Date().timeIntervalSince1970

        if newlyAddedCount > 0 {
            if config.shelfSortPolicy != .manual {
                sortItems(in: config.categories[targetIndex].id, by: config.shelfSortPolicy, shouldSaveAndNotify: false)
            }
            save()
            NotificationCenter.default.post(name: .atoolsShelfDataDidChange, object: nil)
            runtimeLog("[AutoDiscovery] Successfully auto-added \(newlyAddedCount) new app(s) to category: \(config.categories[targetIndex].name)")
        }
    }

    // MARK: - P0-1: 启动项属性深度编辑与自定义图标托管

    /// 将用户选择的 .png / .icns / .jpg / .app 图标归一化缩放裁剪为 256x256 PNG 并托管拷贝至 icons/ 目录
    @discardableResult
    public func importCustomIcon(from sourceURL: URL, for itemId: UUID) -> String? {
        guard let pngData = ThumbnailPipeline.shared.normalizedCustomIconPNGData(from: sourceURL, pixelSize: 256) else {
            return nil
        }
        let iconsDir = iconsDirectoryURL
        let fileName = "\(itemId.uuidString).png"
        let destURL = iconsDir.appendingPathComponent(fileName)

        do {
            try pngData.write(to: destURL, options: .atomic)
            ThumbnailPipeline.shared.invalidateIcon(forPath: destURL.path, customIconPath: destURL.path)
            return destURL.path
        } catch {
            print("[ConfigManager] Failed to save custom icon: \(error)")
            return nil
        }
    }

    /// 若托管在 icons/ 目录下的自定义图标不再被任何启动项引用，则将其从磁盘清理
    public func removeManagedIconIfUnused(_ iconPath: String?, excludingItemId: UUID? = nil) {
        guard let rawPath = iconPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawPath.isEmpty else { return }
        let standardized = (rawPath as NSString).standardizingPath
        let managedPrefix = (iconsDirectoryURL.path as NSString).standardizingPath + "/"
        guard standardized.hasPrefix(managedPrefix) else { return }

        let stillReferenced = config.categories.contains { cat in
            cat.items.contains { item in
                guard item.id != excludingItemId, let custom = item.customIconPath else { return false }
                return (custom as NSString).standardizingPath == standardized
            }
        }
        if !stillReferenced {
            try? fileManager.removeItem(atPath: standardized)
        }
    }

    /// 原位更新启动项属性（保持分类归属与排序位置不变），自动刷新图标缓存并广播通知
    @discardableResult
    public func updateItem(_ updatedItem: LauncherItem, in categoryId: UUID? = nil) -> Bool {
        for catIdx in config.categories.indices {
            if let categoryId = categoryId, config.categories[catIdx].id != categoryId {
                continue
            }
            if let itemIdx = config.categories[catIdx].items.firstIndex(where: { $0.id == updatedItem.id }) {
                let oldItem = config.categories[catIdx].items[itemIdx]
                ThumbnailPipeline.shared.invalidateIcon(forItem: oldItem)
                ThumbnailPipeline.shared.invalidateIcon(forItem: updatedItem)
                config.categories[catIdx].items[itemIdx] = updatedItem
                if oldItem.customIconPath != updatedItem.customIconPath {
                    removeManagedIconIfUnused(oldItem.customIconPath)
                }
                save()
                NotificationCenter.default.post(name: .atoolsShelfDataDidChange, object: nil)
                return true
            }
        }
        return false
    }

    // MARK: - P0-2: 失效启动项检测、目标重新定位与一键清理 (LibraryMaintenance)

    /// 重新定位启动项的目标路径（保持原有 ID、排序位置、自定义名称、自定义图标、启动参数与搜索别名标签不变）
    @discardableResult
    public func relocateItem(id: UUID, in categoryId: UUID? = nil, newTarget: String) -> Bool {
        let trimmedTarget = (newTarget.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).standardizingPath
        guard !trimmedTarget.isEmpty else { return false }

        for catIdx in config.categories.indices {
            if let categoryId = categoryId, config.categories[catIdx].id != categoryId {
                continue
            }
            if let itemIdx = config.categories[catIdx].items.firstIndex(where: { $0.id == id }) {
                var item = config.categories[catIdx].items[itemIdx]
                ThumbnailPipeline.shared.invalidateIcon(forItem: item)
                item.target = trimmedTarget
                if item.itemType == .application || item.itemType == .fileOrFolder {
                    item.itemType = trimmedTarget.lowercased().hasSuffix(".app") ? .application : .fileOrFolder
                }
                config.categories[catIdx].items[itemIdx] = item
                ThumbnailPipeline.shared.invalidateIcon(forItem: item)
                save()
                NotificationCenter.default.post(name: .atoolsShelfDataDidChange, object: nil)
                return true
            }
        }
        return false
    }

    /// 扫描所有分类中的失效启动项（目标文件已被移动或卸载）
    public func scanMissingItems() -> [(category: Category, item: LauncherItem)] {
        var result: [(category: Category, item: LauncherItem)] = []
        for category in config.categories {
            if !config.enableFavoritesCategory && category.isFavorites {
                continue
            }
            for item in category.items where item.checkTargetMissing() {
                result.append((category: category, item: item))
            }
        }
        return result
    }

    /// 一键清理所有分类中的失效启动项，并自动清理孤立的托管自定义图标文件
    @discardableResult
    public func removeAllMissingItems() -> Int {
        var removedItems: [LauncherItem] = []
        for catIdx in config.categories.indices {
            let missingInCat = config.categories[catIdx].items.filter { $0.checkTargetMissing() }
            if !missingInCat.isEmpty {
                removedItems.append(contentsOf: missingInCat)
                config.categories[catIdx].items.removeAll { $0.checkTargetMissing() }
            }
        }
        guard !removedItems.isEmpty else { return 0 }
        for item in removedItems {
            removeManagedIconIfUnused(item.customIconPath)
            ThumbnailPipeline.shared.invalidateIcon(forItem: item)
        }
        save()
        NotificationCenter.default.post(name: .atoolsShelfDataDidChange, object: nil)
        return removedItems.count
    }

    /// 应用从备份或快照恢复的配置，并全量同步刷新各运行时子系统
    public func applyRestoredConfig(_ restored: AtoolsConfig) {
        var normalized = restored
        if !normalized.enableFavoritesCategory && normalized.categories.contains(where: { $0.isFavorites }) {
            normalized.categories.removeAll(where: { $0.isFavorites })
            for i in 0..<normalized.categories.count {
                normalized.categories[i].sortWeight = i
            }
        }
        self.config = normalized
        saveNow()

        ThumbnailPipeline.shared.clearCache()
        ThumbnailPipeline.shared.updateCostLimit(mb: normalized.thumbnailCacheLimitMB)
        SpotlightBridge.shared.setExtraHotFolders(normalized.extraHotFolders)
        SpotlightBridge.shared.dropHotFolderCache()
        SearchExclusionEngine.shared.recompile(config: normalized)
        TrackpadGestureManager.shared.updateConfiguration(normalized.shelfTrackpadGesture)

        if normalized.enableShelfPanel {
            HotkeyManager.shared.register(id: .shelf, binding: normalized.shelfHotkey)
        } else {
            HotkeyManager.shared.unregister(id: .shelf)
        }
        if normalized.enableSearchPanel {
            HotkeyManager.shared.register(id: .search, binding: normalized.searchHotkey)
        } else {
            HotkeyManager.shared.unregister(id: .search)
        }

        NotificationCenter.default.post(name: .atoolsThemeDidChange, object: nil)
        NotificationCenter.default.post(name: .atoolsCategoryOrientationDidChange, object: nil)
        NotificationCenter.default.post(name: .atoolsShelfIconSizeDidChange, object: nil)
        NotificationCenter.default.post(name: .atoolsFavoritesToggleDidChange, object: nil)
        NotificationCenter.default.post(name: .atoolsPanelTogglesDidChange, object: nil)
        NotificationCenter.default.post(name: .atoolsAutoQuitDidChange, object: nil)
        NotificationCenter.default.post(name: .atoolsAutoPasteOnSummonDidChange, object: nil)
        NotificationCenter.default.post(name: .atoolsShelfDataDidChange, object: nil)
    }

    @discardableResult
    public func addCategory(name: String, iconSymbol: String = "folder.fill") -> Category {
        let safeName = CategorySanitizer.sanitize(name) ?? "新分类"
        let newCat = Category(
            name: safeName,
            iconSymbol: iconSymbol,
            sortWeight: self.config.categories.count,
            items: []
        )
        self.config.categories.append(newCat)
        save()
        return newCat
    }

    public func renameCategory(id: UUID, newName: String, newIcon: String? = nil) {
        guard let safeName = CategorySanitizer.sanitize(newName), !safeName.isEmpty else { return }
        if let idx = self.config.categories.firstIndex(where: { $0.id == id }) {
            self.config.categories[idx].name = safeName
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
        } else {
            for item in categoryToDelete.items {
                removeManagedIconIfUnused(item.customIconPath, excludingItemId: item.id)
            }
        }

        self.config.categories.remove(at: idx)
        for i in 0..<self.config.categories.count {
            self.config.categories[i].sortWeight = i
        }
        if self.config.autoAddTargetCategoryId == id {
            self.config.autoAddTargetCategoryId = nil
            self.config.autoAddPolicyMode = .dedicatedInbox
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

    public func updateSearchFilterOrder(_ order: [String]) {
        self.config.searchFilterOrder = order
        save()
    }
}
